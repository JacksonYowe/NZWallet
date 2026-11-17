// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// A message pipe between holder and reader (Bluetooth, or in-memory for the same-phone demo).
protocol MDLTransport: AnyObject {
    var onMessage: ((Data) -> Void)? { get set }
    var onClose: (() -> Void)? { get set }
    func send(_ data: Data)
    func close()
}

/// In-memory pair of transports. `async` delivers on the main queue (UI demo); otherwise synchronously (tests).
final class LoopbackTransport: MDLTransport {
    var onMessage: ((Data) -> Void)?
    var onClose: (() -> Void)?
    weak var peer: LoopbackTransport?
    /// Test hook: rewrites outgoing messages (man-in-the-middle simulation).
    var tap: ((Data) -> Data)?
    private let async: Bool

    private init(async: Bool) { self.async = async }

    static func pair(async: Bool = true) -> (LoopbackTransport, LoopbackTransport) {
        let a = LoopbackTransport(async: async), b = LoopbackTransport(async: async)
        a.peer = b; b.peer = a
        return (a, b)
    }

    func send(_ data: Data) {
        guard let peer else { return }
        let data = tap?(data) ?? data
        if async { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { peer.onMessage?(data) } }
        else { peer.onMessage?(data) }
    }

    func close() {
        let p = peer
        peer = nil
        p?.peer = nil
        if async { DispatchQueue.main.async { p?.onClose?() } } else { p?.onClose?() }
    }
}

enum MDLSessionStatus: Int {
    case decryptionError = 10, cborError = 11, sessionTermination = 20
}

// MARK: - Holder

/// The citizen's side: shows the engagement QR, receives a request, sends approved items.
final class MDLHolderSession {
    enum State: Equatable { case waiting, connected, requested(MDLItemsRequest), sent, declined, failed(String), closed }

    let engagement: DeviceEngagement
    private let eDeviceKey = P256.KeyAgreement.PrivateKey()
    private let document: IssuedMDoc
    private let deviceSigner: (Data) throws -> Data
    private var keys: MDLSessionKeys?
    private var transport: MDLTransport?

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .waiting { didSet { onStateChange?(state) } }

    init(document: IssuedMDoc, deviceSigner: @escaping (Data) throws -> Data, serviceUUID: UUID = UUID()) {
        self.document = document
        self.deviceSigner = deviceSigner
        engagement = DeviceEngagement(eDeviceKey: eDeviceKey.publicKey, serviceUUID: serviceUUID)
    }

    var availableElements: [String: [String]] { document.available }

    func attach(_ t: MDLTransport) {
        transport = t
        t.onMessage = { [weak self] in self?.receive($0) }
        t.onClose = { [weak self] in
            guard let self else { return }
            switch state {
            case .waiting, .connected, .requested: state = .closed
            default: break   // keep sent / declined / failed visible
            }
        }
        state = .connected
    }

    private func receive(_ data: Data) {
        guard let msg = try? CBOR.decode(data) else { return fail("cbor") }
        if keys == nil {
            // SessionEstablishment
            guard let ekC = msg["eReaderKey"], ekC.embeddedRaw != nil, let ekRaw = ekC.embeddedRaw,
                  let ek = try? CBOR.decode(ekRaw), let ekX963 = COSE.x963(fromKey: ek),
                  let enc = msg["data"]?.bytes else { return fail("establishment") }
            do {
                keys = try MDLSessionKeys(engagementRaw: engagement.raw, eReaderKeyBytes: ekC.encoded(),
                                          privateKey: eDeviceKey, peerPublicX963: ekX963, isReader: false)
                guard let plain = try keys?.decrypt(enc), let req = MDLItemsRequest.parse(plain) else { return fail("request") }
                state = .requested(req)
            } catch { fail("decrypt") }
        } else if msg["status"]?.int == MDLSessionStatus.sessionTermination.rawValue {
            transport?.close()
            if case .sent = state {} else { state = .closed }
        }
    }

    /// Sends only the approved elements (namespace → ids).
    func approve(_ approved: [String: Set<String>]) {
        guard var k = keys else { return }
        do {
            let resp = try MDLResponseBuilder.build(document: document, approved: approved,
                                                    transcript: k.transcript, deviceSigner: deviceSigner)
            let enc = try k.encrypt(resp)
            keys = k
            transport?.send(CBOR.map([(.text("data"), .bytes(enc)), (.text("status"), .int(20))]).encoded())
            state = .sent
        } catch { fail("sign") }
    }

    func decline() {
        transport?.send(CBOR.map([(.text("status"), .int(20))]).encoded())
        transport?.close()
        state = .declined
    }

    func cancel() { transport?.close(); transport = nil }

    private func fail(_ reason: String) {
        transport?.send(CBOR.map([(.text("status"), .int(MDLSessionStatus.cborError.rawValue))]).encoded())
        transport?.close()
        state = .failed(reason)
    }
}

// MARK: - Reader

/// The checker's side: parses the QR, sends an encrypted request, verifies the response.
final class MDLReaderSession {
    enum State { case idle, requesting, done(MDLVerification), failed(String) }

    let engagement: DeviceEngagement
    let request: MDLItemsRequest
    private let trustedIACAKeys: [Data]
    private let eReaderKey = P256.KeyAgreement.PrivateKey()
    private var keys: MDLSessionKeys?
    private var transport: MDLTransport?

    var onStateChange: ((State) -> Void)?
    private(set) var state: State = .idle { didSet { onStateChange?(state) } }

    init?(qr: String, request: MDLItemsRequest, trustedIACAKeys: [Data]) {
        guard let e = DeviceEngagement(qr: qr) else { return nil }
        engagement = e
        self.request = request
        self.trustedIACAKeys = trustedIACAKeys
    }

    func start(_ t: MDLTransport) {
        transport = t
        t.onMessage = { [weak self] in self?.receive($0) }
        t.onClose = { [weak self] in
            guard let self else { return }
            if case .requesting = state { state = .failed("mdl.reason.declined") }
        }
        do {
            let ekBytes = CBOR.embedded(COSE.key(x963: eReaderKey.publicKey.x963Representation)).encoded()
            var k = try MDLSessionKeys(engagementRaw: engagement.raw, eReaderKeyBytes: ekBytes,
                                       privateKey: eReaderKey, peerPublicX963: engagement.eDeviceKeyX963, isReader: true)
            let enc = try k.encrypt(request.deviceRequest)
            keys = k
            state = .requesting
            t.send(CBOR.map([(.text("eReaderKey"), try CBOR.decode(ekBytes)), (.text("data"), .bytes(enc))]).encoded())
        } catch { state = .failed("mdl.reason.session") }
    }

    private func receive(_ data: Data) {
        guard let msg = try? CBOR.decode(data) else { state = .failed("mdl.reason.format"); return }
        if let enc = msg["data"]?.bytes, var k = keys {
            guard let plain = try? k.decrypt(enc) else { state = .failed("mdl.reason.decrypt"); return }
            keys = k
            let v = MDLVerifier.verify(responseBytes: plain, request: request, transcript: k.transcript,
                                       trustedIACAKeys: trustedIACAKeys)
            state = .done(v)
            transport?.close()
        } else if msg["status"] != nil {
            if case .requesting = state { state = .failed("mdl.reason.declined") }
            transport?.close()
        }
    }

    func cancel() { transport?.close() }
}

/// Requests for the three in-person checks, using standard ISO element names.
extension Scenario {
    var mdlRequest: MDLItemsRequest {
        let ids: [String] = switch self {
        case .age: ["portrait", "age_over_18"]
        case .identity: ["portrait", "family_name", "given_name", "birth_date", "document_number"]
        case .driver: ["portrait", "family_name", "given_name", "document_number", "driving_privileges", "expiry_date"]
        }
        var req = [MDL.namespace: Dictionary(uniqueKeysWithValues: ids.map { ($0, false) })]
        // NZ checks also ask for the card version (needed to confirm the physical card is current).
        if self != .age { req[MDL.domesticNamespace] = ["card_version": false] }
        return MDLItemsRequest(elements: req)
    }
}
