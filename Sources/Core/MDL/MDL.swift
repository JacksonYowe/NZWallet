// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// ISO/IEC 18013-5 mobile driving licence (mDL) data structures, implemented
/// from the published standard. Same formats as other 18013-5 wallets and
/// readers (e.g. the NSW Digital Driver Licence), so either side can read the other.
enum MDL {
    static let docType = "org.iso.18013.5.1.mDL"
    static let namespace = "org.iso.18013.5.1"
    /// Domestic namespace for NZ fields that ISO does not define (card version, endorsements, donor).
    static let domesticNamespace = "nz.test.mdl.1"
    static let version = "1.0"
}

// MARK: - Issuer side

/// A licence as stored in the wallet: issuer-signed items plus the issuer's MSO signature.
struct IssuedMDoc {
    /// namespace → encoded IssuerSignedItemBytes (#6.24 wrapped), exactly as digested by the issuer.
    let items: [String: [Data]]
    let issuerAuth: COSE.Sign1
    let validUntil: Date

    /// Element identifiers available, per namespace.
    var available: [String: [String]] {
        items.mapValues { $0.compactMap { (try? CBOR.decode($0))?.embeddedRaw.flatMap { try? CBOR.decode($0) }?["elementIdentifier"]?.text } }
    }
}

/// Demo issuing authority. The IACA key is a fixed DEMO key so every install
/// trusts the same root; in production it is held in a government HSM.
struct MDLIssuer {
    static let iacaName = X509.Name(country: "NZ", commonName: "TEST NZ mDL IACA (not for production)")
    static let dsName = X509.Name(country: "NZ", commonName: "TEST NZ mDL Document Signer")
    // DEMO ONLY. Never ship a private key in an app.
    private static let iacaSeed = Data(SHA256.hash(data: Data("nz-services-test-iaca-v1".utf8)))
    static let iacaKey = try! P256.Signing.PrivateKey(rawRepresentation: iacaSeed)
    static var iacaPublicKey: Data { iacaKey.publicKey.x963Representation }

    let dsKey = P256.Signing.PrivateKey()
    let iacaCert: Data
    let dsCert: Data

    init(now: Date = Date()) {
        let year: TimeInterval = 365 * 86_400
        iacaCert = try! X509.certificate(subject: Self.iacaName, issuer: Self.iacaName,
                                         subjectKey: Self.iacaPublicKey, issuerKeyX963: Self.iacaPublicKey,
                                         serial: 1, notBefore: now - year, notAfter: now + 10 * year,
                                         isCA: true, signer: Self.iacaKey)
        dsCert = try! X509.certificate(subject: Self.dsName, issuer: Self.iacaName,
                                       subjectKey: dsKey.publicKey.x963Representation,
                                       issuerKeyX963: Self.iacaPublicKey, serial: Int.random(in: 2...Int(Int32.max)),
                                       notBefore: now - 86_400, notAfter: now + 365 * 86_400,   // ISO 18013-5 Annex B: ≤ 457 days
                                       isCA: false, signer: Self.iacaKey)
    }

    /// Issues an mDL bound to the holder's device key.
    func issue(elements: [String: [(String, CBOR)]], deviceKeyX963: Data,
               signed: Date, validFrom: Date, validUntil: Date,
               signer: ((Data) throws -> Data)? = nil) -> IssuedMDoc {
        var items = [String: [Data]]()
        var digests = [(CBOR, CBOR)]()
        var digestID = 0
        for (ns, list) in elements.sorted(by: { $0.key < $1.key }) {
            var nsDigests = [(CBOR, CBOR)]()
            for (id, value) in list {
                var salt = [UInt8](repeating: 0, count: 16)
                _ = SecRandomCopyBytes(kSecRandomDefault, salt.count, &salt)
                let item = CBOR.map([(.text("digestID"), .int(digestID)), (.text("random"), .bytes(Data(salt))),
                                     (.text("elementIdentifier"), .text(id)), (.text("elementValue"), value)])
                let bytes = CBOR.embedded(item).encoded()
                items[ns, default: []].append(bytes)
                nsDigests.append((.int(digestID), .bytes(Data(SHA256.hash(data: bytes)))))
                digestID += 1
            }
            digests.append((.text(ns), .map(nsDigests)))
        }
        let mso = CBOR.map([
            (.text("version"), .text(MDL.version)),
            (.text("digestAlgorithm"), .text("SHA-256")),
            (.text("valueDigests"), .map(digests)),
            (.text("deviceKeyInfo"), .map([(.text("deviceKey"), COSE.key(x963: deviceKeyX963))])),
            (.text("docType"), .text(MDL.docType)),
            (.text("validityInfo"), .map([(.text("signed"), .tdate(signed)), (.text("validFrom"), .tdate(validFrom)),
                                          (.text("validUntil"), .tdate(validUntil))])),
        ])
        let payload = CBOR.embedded(mso).encoded()
        let auth = try! COSE.Sign1.sign(payload: payload, x5chain: [dsCert], signer: signer ?? COSE.rawSigner(dsKey))
        return IssuedMDoc(items: items, issuerAuth: auth, validUntil: validUntil)
    }
}

// MARK: - Device engagement (the QR code)

struct DeviceEngagement {
    enum BLEMode { case peripheralServer, centralClient }

    let raw: Data                       // DeviceEngagement CBOR bytes, as encoded / as scanned
    let eDeviceKeyBytes: Data           // EDeviceKeyBytes (#6.24 COSE_Key), encoded
    let eDeviceKeyX963: Data
    let peripheralServerUUID: UUID?
    let centralClientUUID: UUID?

    var qrString: String { "mdoc:" + raw.base64URL }

    /// Holder: engagement for BLE mdoc peripheral server mode.
    init(eDeviceKey: P256.KeyAgreement.PublicKey, serviceUUID: UUID) {
        let keyItem = CBOR.embedded(COSE.key(x963: eDeviceKey.x963Representation))
        let uuidBytes = withUnsafeBytes(of: serviceUUID.uuid) { Data($0) }
        let ble = CBOR.array([.int(2), .int(1), .map([(.int(0), .bool(true)), (.int(1), .bool(false)),
                                                         (.int(10), .bytes(uuidBytes))])])
        let de = CBOR.map([(.int(0), .text(MDL.version)),
                           (.int(1), .array([.int(1), keyItem])),
                           (.int(2), .array([ble]))])
        raw = de.encoded()
        eDeviceKeyBytes = keyItem.encoded()
        eDeviceKeyX963 = eDeviceKey.x963Representation
        peripheralServerUUID = serviceUUID
        centralClientUUID = nil
    }

    /// Reader: parse a scanned `mdoc:` QR code.
    init?(qr: String) {
        let s = qr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("mdoc:"), let data = Data(base64URL: String(s.dropFirst(5))),
              let de = try? CBOR.decode(data),
              let security = de[1]?.array, security.count >= 2, security[0].int == 1,
              let keyRaw = security[1].embeddedRaw, let key = try? CBOR.decode(keyRaw),
              let x963 = COSE.x963(fromKey: key) else { return nil }
        raw = data
        eDeviceKeyBytes = security[1].encoded()
        eDeviceKeyX963 = x963
        var ps: UUID?, cc: UUID?
        for m in de[2]?.array ?? [] {
            guard let a = m.array, a.count >= 3, a[0].int == 2 else { continue }
            let opts = a[2]
            if opts[0]?.bool == true, let u = opts[10]?.bytes, u.count == 16 { ps = UUID(bytes: u) }
            if opts[1]?.bool == true, let u = opts[11]?.bytes, u.count == 16 { cc = UUID(bytes: u) }
        }
        peripheralServerUUID = ps
        centralClientUUID = cc
    }
}

extension UUID {
    init(bytes d: Data) {
        let b = [UInt8](d)
        self.init(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                         b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

// MARK: - Session transcript and encryption (18013-5 §9.1.1)

struct MDLSessionKeys {
    let transcript: CBOR                  // SessionTranscript (QR engagement: Handover = null)
    let transcriptBytes: Data             // #6.24 wrapped, encoded
    private let skReader: SymmetricKey
    private let skDevice: SymmetricKey
    private let isReader: Bool
    private var sendCounter: UInt32 = 1
    private var receiveCounter: UInt32 = 1

    init(engagementRaw: Data, eReaderKeyBytes: Data, privateKey: P256.KeyAgreement.PrivateKey,
         peerPublicX963: Data, isReader: Bool) throws {
        transcript = .array([.embeddedBytes(engagementRaw), try CBOR.decode(eReaderKeyBytes), .null])
        transcriptBytes = CBOR.embedded(transcript).encoded()
        let peer = try P256.KeyAgreement.PublicKey(x963Representation: peerPublicX963)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: peer)
        let salt = Data(SHA256.hash(data: transcriptBytes))
        skReader = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("SKReader".utf8), outputByteCount: 32)
        skDevice = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("SKDevice".utf8), outputByteCount: 32)
        self.isReader = isReader
    }

    private static func iv(device: Bool, counter: UInt32) -> Data {
        Data([0, 0, 0, 0, 0, 0, 0, device ? 1 : 0]) + withUnsafeBytes(of: counter.bigEndian) { Data($0) }
    }

    mutating func encrypt(_ plain: Data) throws -> Data {
        let key = isReader ? skReader : skDevice
        let box = try AES.GCM.seal(plain, using: key, nonce: AES.GCM.Nonce(data: Self.iv(device: !isReader, counter: sendCounter)))
        sendCounter += 1
        return box.ciphertext + box.tag
    }

    mutating func decrypt(_ data: Data) throws -> Data {
        guard data.count >= 16 else { throw CBORError.truncated }
        let key = isReader ? skDevice : skReader
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: Self.iv(device: isReader, counter: receiveCounter)),
                                        ciphertext: data.dropLast(16), tag: data.suffix(16))
        let plain = try AES.GCM.open(box, using: key)
        receiveCounter += 1
        return plain
    }
}

// MARK: - Requests and responses

/// What the reader asks for: namespace → [element identifier: intent to retain].
struct MDLItemsRequest: Equatable {
    var elements: [String: [String: Bool]]

    var cbor: CBOR {
        let ns = elements.sorted { $0.key < $1.key }.map { (CBOR.text($0.key), CBOR.map($0.value.sorted { $0.key < $1.key }.map { (.text($0.key), .bool($0.value)) })) }
        return .map([(.text("docType"), .text(MDL.docType)), (.text("nameSpaces"), .map(ns))])
    }

    var deviceRequest: Data {
        CBOR.map([(.text("version"), .text(MDL.version)),
                  (.text("docRequests"), .array([.map([(.text("itemsRequest"), .embedded(cbor))])]))]).encoded()
    }

    /// Parses a DeviceRequest; only mDL doc requests are kept.
    static func parse(_ data: Data) -> MDLItemsRequest? {
        guard let req = try? CBOR.decode(data), let docs = req["docRequests"]?.array else { return nil }
        var out = [String: [String: Bool]]()
        for d in docs {
            guard let raw = d["itemsRequest"]?.embeddedRaw, let ir = try? CBOR.decode(raw),
                  ir["docType"]?.text == MDL.docType else { continue }
            for p in ir["nameSpaces"]?.pairs ?? [] {
                guard let ns = p.key.text else { continue }
                for e in p.value.pairs ?? [] { if let id = e.key.text { out[ns, default: [:]][id] = e.value.bool ?? false } }
            }
        }
        return out.isEmpty ? nil : MDLItemsRequest(elements: out)
    }
}

enum MDLResponseBuilder {
    /// Builds a DeviceResponse with only the approved elements, signed by the device key over this session.
    static func build(document: IssuedMDoc, approved: [String: Set<String>], transcript: CBOR,
                      deviceSigner: (Data) throws -> Data) throws -> Data {
        var ns = [(CBOR, CBOR)]()
        for (name, items) in document.items.sorted(by: { $0.key < $1.key }) {
            let keep = approved[name] ?? []
            let chosen = items.filter { bytes in
                guard let raw = (try? CBOR.decode(bytes))?.embeddedRaw, let item = try? CBOR.decode(raw),
                      let id = item["elementIdentifier"]?.text else { return false }
                return keep.contains(id)
            }
            if !chosen.isEmpty { ns.append((.text(name), .array(try chosen.map { try CBOR.decode($0) }))) }
        }
        let deviceNameSpacesBytes = CBOR.embedded(.map([CBORPair]()))
        let auth = CBOR.array([.text("DeviceAuthentication"), transcript, .text(MDL.docType), deviceNameSpacesBytes])
        let authBytes = CBOR.embedded(auth).encoded()
        let sig = try COSE.Sign1.sign(payload: authBytes, detached: true, signer: deviceSigner)
        let doc = CBOR.map([
            (.text("docType"), .text(MDL.docType)),
            (.text("issuerSigned"), .map([(.text("nameSpaces"), .map(ns)), (.text("issuerAuth"), document.issuerAuth.cbor)])),
            (.text("deviceSigned"), .map([(.text("nameSpaces"), deviceNameSpacesBytes),
                                          (.text("deviceAuth"), .map([(.text("deviceSignature"), sig.cbor)]))])),
        ])
        return CBOR.map([(.text("version"), .text(MDL.version)), (.text("documents"), .array([doc])),
                         (.text("status"), .int(0))]).encoded()
    }
}

// MARK: - Reader verification

struct MDLCheck: Identifiable, Equatable {
    let id: String          // localisation key
    let passed: Bool
}

struct MDLVerification {
    enum Outcome: Equatable { case valid, untrustedIssuer, invalid(String), expired }
    var outcome: Outcome
    var checks: [MDLCheck]
    var elements: [String: [String: CBOR]] = [:]      // namespace → id → value
    var missing: [String] = []
    var issuerName: String?
    var issuerCountry: String?

    func value(_ id: String, ns: String = MDL.namespace) -> CBOR? { elements[ns]?[id] }
}

enum MDLVerifier {
    /// Verifies a decrypted DeviceResponse against this session.
    static func verify(responseBytes: Data, request: MDLItemsRequest, transcript: CBOR,
                       trustedIACAKeys: [Data], now: Date = Date()) -> MDLVerification {
        var checks = [MDLCheck]()
        func done(_ o: MDLVerification.Outcome, _ key: String) -> MDLVerification {
            checks.append(MDLCheck(id: key, passed: false))
            return MDLVerification(outcome: o, checks: checks)
        }
        guard let resp = try? CBOR.decode(responseBytes), let doc = resp["documents"]?.array?.first else {
            return done(.invalid("mdl.reason.noDocument"), "mdl.check.format")
        }
        guard doc["docType"]?.text == MDL.docType,
              let issuerSigned = doc["issuerSigned"], let authC = issuerSigned["issuerAuth"],
              let auth = COSE.Sign1(authC), let payload = auth.payload,
              let msoRaw = (try? CBOR.decode(payload))?.embeddedRaw, let mso = try? CBOR.decode(msoRaw),
              mso["docType"]?.text == MDL.docType else {
            return done(.invalid("mdl.reason.format"), "mdl.check.format")
        }
        checks.append(MDLCheck(id: "mdl.check.format", passed: true))

        // 1. Issuer certificate chain → trusted IACA
        guard let dsDER = auth.x5chain.first, let ds = try? X509.Parsed(dsDER) else {
            return done(.invalid("mdl.reason.noCertificate"), "mdl.check.issuerTrusted")
        }
        let trusted = trustedIACAKeys.contains { ds.isSigned(byX963: $0) }
        var result = MDLVerification(outcome: .valid, checks: [], issuerName: ds.subjectCN, issuerCountry: ds.country)

        // 1b. Certificate profile rules (ISO 18013-5 Annex B, enforced by NSW and other readers)
        if let a = ds.notBefore, let b = ds.notAfter, b.timeIntervalSince(a) > 457 * 86_400 {
            return done(.invalid("mdl.reason.certificateProfile"), "mdl.check.issuerTrusted")
        }

        // 2. MSO signature by the document signer
        guard auth.verify(publicKeyX963: ds.publicKeyX963) else {
            return done(.invalid("mdl.reason.issuerSignature"), "mdl.check.issuerSignature")
        }
        checks.append(MDLCheck(id: "mdl.check.issuerTrusted", passed: trusted && ds.isValid(at: now)))
        checks.append(MDLCheck(id: "mdl.check.issuerSignature", passed: true))

        // 3. Each returned element matches its signed digest
        var elements = [String: [String: CBOR]]()
        for p in issuerSigned["nameSpaces"]?.pairs ?? [] {
            guard let ns = p.key.text else { continue }
            for itemC in p.value.array ?? [] {
                let bytes = itemC.encoded()
                guard let raw = itemC.embeddedRaw, let item = try? CBOR.decode(raw),
                      let did = item["digestID"]?.int, let id = item["elementIdentifier"]?.text, let v = item["elementValue"],
                      mso["valueDigests"]?[ns]?[did]?.bytes == Data(SHA256.hash(data: bytes)) else {
                    return done(.invalid("mdl.reason.tampered"), "mdl.check.integrity")
                }
                elements[ns, default: [:]][id] = v
            }
        }
        checks.append(MDLCheck(id: "mdl.check.integrity", passed: true))

        // 4. Device signature over this session (proves the phone holds the key; stops replay and copies)
        guard let dkC = mso["deviceKeyInfo"]?["deviceKey"], let dk = COSE.x963(fromKey: dkC),
              let dsigC = doc["deviceSigned"]?["deviceAuth"]?["deviceSignature"], let dsig = COSE.Sign1(dsigC),
              let dns = doc["deviceSigned"]?["nameSpaces"] else {
            return done(.invalid("mdl.reason.deviceSignature"), "mdl.check.deviceSignature")
        }
        let authBytes = CBOR.embedded(.array([.text("DeviceAuthentication"), transcript, .text(MDL.docType), dns])).encoded()
        guard dsig.verify(publicKeyX963: dk, detachedPayload: authBytes) else {
            return done(.invalid("mdl.reason.deviceSignature"), "mdl.check.deviceSignature")
        }
        checks.append(MDLCheck(id: "mdl.check.deviceSignature", passed: true))

        // 5. Validity period
        let v = mso["validityInfo"]
        guard let from = v?["validFrom"]?.date, let until = v?["validUntil"]?.date, from <= now, now <= until else {
            checks.append(MDLCheck(id: "mdl.check.validity", passed: false))
            result.outcome = .expired; result.checks = checks; result.elements = elements
            return result
        }
        checks.append(MDLCheck(id: "mdl.check.validity", passed: true))

        // 5b. Date rules: signed ≤ validFrom, and signed within the signer certificate's validity
        if let signed = v?["signed"]?.date {
            if signed > from { return done(.invalid("mdl.reason.dates"), "mdl.check.validity") }
            if let nb = ds.notBefore, signed < nb { return done(.invalid("mdl.reason.dates"), "mdl.check.validity") }
        }
        // 5c. issuing_country must match the signer certificate's country
        if let c = elements[MDL.namespace]?["issuing_country"]?.text, let dc = ds.country, c != dc {
            return done(.invalid("mdl.reason.certificateProfile"), "mdl.check.issuerTrusted")
        }

        // 6. Requested elements present
        let missing = request.elements.flatMap { ns, ids in ids.keys.filter { elements[ns]?[$0] == nil } }.sorted()
        checks.append(MDLCheck(id: "mdl.check.requested", passed: missing.isEmpty))

        result.checks = checks
        result.elements = elements
        result.missing = missing
        result.outcome = trusted && ds.isValid(at: now) ? .valid : .untrustedIssuer
        return result
    }
}
