// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CoreBluetooth
import CryptoKit

/// ISO/IEC 18013-5 §8.3.3 Bluetooth Low Energy transport, written from the standard.
///
/// - mdoc peripheral server mode: the holder's phone is the GATT server (characteristics 1–4).
/// - mdoc central client mode: the reader is the GATT server (characteristics 5–8).
/// In both, the GATT client writes to Client2Server and the server notifies on Server2Client.
/// Messages are split into chunks whose first byte is 0x01 (more follows) or 0x00 (last).
/// The State characteristic carries 0x01 (start) and 0x02 (end).
enum MDLBLE {
    struct Characteristics {
        let state, client2Server, server2Client, ident: CBUUID
    }
    private static func uuid(_ n: Int) -> CBUUID { CBUUID(string: String(format: "%08X-A123-48CE-896B-4C76973373E6", n)) }
    static let peripheralServer = Characteristics(state: uuid(1), client2Server: uuid(2), server2Client: uuid(3), ident: uuid(4))
    static let centralClient = Characteristics(state: uuid(5), client2Server: uuid(6), server2Client: uuid(7), ident: uuid(8))

    static let start = Data([0x01]), end = Data([0x02])

    /// BLEIdent = HKDF-SHA-256(EDeviceKeyBytes, salt: "", info: "BLEIdent", 16 bytes).
    static func ident(eDeviceKeyBytes: Data) -> Data {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: eDeviceKeyBytes), salt: Data(),
                               info: Data("BLEIdent".utf8), outputByteCount: 16).withUnsafeBytes { Data($0) }
    }

    static func chunks(_ data: Data, size: Int) -> [Data] {
        let n = max(size - 1, 1)
        var out = [Data](), i = data.startIndex
        repeat {
            let j = min(i + n, data.endIndex)
            out.append(Data([j == data.endIndex ? 0x00 : 0x01]) + data[i..<j])
            i = j
        } while i < data.endIndex
        return out
    }
}

enum MDLBLEError: String { case unsupported, unauthorized, poweredOff, timeout, disconnected }

/// Reassembles chunked messages.
private struct Reassembler {
    var buffer = Data()
    mutating func add(_ chunk: Data) -> Data? {
        guard let flag = chunk.first else { return nil }
        buffer += chunk.dropFirst()
        guard flag == 0x00 else { return nil }
        defer { buffer = Data() }
        return buffer
    }
}

// MARK: - GATT server (holder in peripheral server mode; reader in central client mode)

final class MDLGATTServer: NSObject, MDLTransport, CBPeripheralManagerDelegate {
    var onMessage: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onConnected: (() -> Void)?
    var onError: ((MDLBLEError) -> Void)?

    private let serviceUUID: CBUUID
    private let chars: MDLBLE.Characteristics
    private let identValue: Data
    private var manager: CBPeripheralManager!
    private var stateChar, c2sChar, s2cChar: CBMutableCharacteristic?
    private var central: CBCentral?
    private var reassembler = Reassembler()
    private var outbox = [Data]()
    private var closed = false

    init(serviceUUID: UUID, characteristics: MDLBLE.Characteristics, ident: Data) {
        self.serviceUUID = CBUUID(nsuuid: serviceUUID)
        chars = characteristics
        identValue = ident
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: .main)
    }

    func peripheralManagerDidUpdateState(_ p: CBPeripheralManager) {
        switch p.state {
        case .poweredOn:
            let state = CBMutableCharacteristic(type: chars.state, properties: [.notify, .writeWithoutResponse], value: nil, permissions: [.writeable])
            let c2s = CBMutableCharacteristic(type: chars.client2Server, properties: [.writeWithoutResponse], value: nil, permissions: [.writeable])
            let s2c = CBMutableCharacteristic(type: chars.server2Client, properties: [.notify], value: nil, permissions: [])
            let ident = CBMutableCharacteristic(type: chars.ident, properties: [.read], value: identValue, permissions: [.readable])
            let service = CBMutableService(type: serviceUUID, primary: true)
            service.characteristics = [state, c2s, s2c, ident]
            stateChar = state; c2sChar = c2s; s2cChar = s2c
            p.add(service)
        case .unsupported: onError?(.unsupported)
        case .unauthorized: onError?(.unauthorized)
        case .poweredOff: onError?(.poweredOff)
        default: break
        }
    }

    func peripheralManager(_ p: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        guard error == nil, !closed else { return }
        p.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID]])
    }

    func peripheralManager(_ p: CBPeripheralManager, central c: CBCentral, didSubscribeTo ch: CBCharacteristic) {
        central = c
    }

    func peripheralManager(_ p: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for r in requests {
            guard let v = r.value else { continue }
            if r.characteristic.uuid == chars.state {
                if v == MDLBLE.start { central = r.central; p.stopAdvertising(); onConnected?() }
                else if v == MDLBLE.end { finish(notify: false) }
            } else if r.characteristic.uuid == chars.client2Server, let msg = reassembler.add(v) {
                onMessage?(msg)
            }
        }
    }

    func peripheralManager(_ p: CBPeripheralManager, didReceiveRead r: CBATTRequest) {
        if r.characteristic.uuid == chars.ident { r.value = identValue; p.respond(to: r, withResult: .success) }
        else { p.respond(to: r, withResult: .readNotPermitted) }
    }

    func send(_ data: Data) {
        let size = central?.maximumUpdateValueLength ?? 20
        outbox += MDLBLE.chunks(data, size: size)
        pump()
    }

    private func pump() {
        guard let s2c = s2cChar else { return }
        while let next = outbox.first {
            guard manager.updateValue(next, for: s2c, onSubscribedCentrals: central.map { [$0] }) else { return }
            outbox.removeFirst()
        }
    }

    func peripheralManagerIsReady(toUpdateSubscribers p: CBPeripheralManager) { pump() }

    func close() { finish(notify: true) }

    private func finish(notify: Bool) {
        guard !closed else { return }
        closed = true
        if notify, let st = stateChar { manager.updateValue(MDLBLE.end, for: st, onSubscribedCentrals: nil) }
        // Let queued chunks and the end signal go out before tearing down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            manager.stopAdvertising()
            manager.removeAllServices()
            onClose?()
        }
    }
}

// MARK: - GATT client (reader in peripheral server mode)

final class MDLGATTClient: NSObject, MDLTransport, CBCentralManagerDelegate, CBPeripheralDelegate {
    var onMessage: ((Data) -> Void)?
    var onClose: (() -> Void)?
    var onConnected: (() -> Void)?
    var onError: ((MDLBLEError) -> Void)?

    private let serviceUUID: CBUUID
    private let chars: MDLBLE.Characteristics
    private var manager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var stateChar, c2sChar, s2cChar: CBCharacteristic?
    private var notifying = Set<CBUUID>()
    private var reassembler = Reassembler()
    private var outbox = [Data]()
    private var closed = false

    init(serviceUUID: UUID, characteristics: MDLBLE.Characteristics) {
        self.serviceUUID = CBUUID(nsuuid: serviceUUID)
        chars = characteristics
        super.init()
        manager = CBCentralManager(delegate: self, queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, stateChar == nil, !closed else { return }
            onError?(.timeout); finish()
        }
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: c.scanForPeripherals(withServices: [serviceUUID])
        case .unsupported: onError?(.unsupported)
        case .unauthorized: onError?(.unauthorized)
        case .poweredOff: onError?(.poweredOff)
        default: break
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral == nil else { return }
        c.stopScan()
        peripheral = p
        p.delegate = self
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) { p.discoverServices([serviceUUID]) }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if !closed { onError?(.disconnected); finish() }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == serviceUUID }) else { return finish() }
        p.discoverCharacteristics([chars.state, chars.client2Server, chars.server2Client], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            switch ch.uuid {
            case chars.state: stateChar = ch; p.setNotifyValue(true, for: ch)
            case chars.client2Server: c2sChar = ch
            case chars.server2Client: s2cChar = ch; p.setNotifyValue(true, for: ch)
            default: break
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if ch.isNotifying { notifying.insert(ch.uuid) }
        guard notifying.contains(chars.state), notifying.contains(chars.server2Client), let st = stateChar else { return }
        p.writeValue(MDLBLE.start, for: st, type: .withoutResponse)
        onConnected?()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard let v = ch.value else { return }
        if ch.uuid == chars.server2Client, let msg = reassembler.add(v) { onMessage?(msg) }
        else if ch.uuid == chars.state, v == MDLBLE.end { finish() }
    }

    func send(_ data: Data) {
        guard let p = peripheral else { return }
        outbox += MDLBLE.chunks(data, size: p.maximumWriteValueLength(for: .withoutResponse))
        pump()
    }

    private func pump() {
        guard let p = peripheral, let c2s = c2sChar else { return }
        while let next = outbox.first, p.canSendWriteWithoutResponse {
            p.writeValue(next, for: c2s, type: .withoutResponse)
            outbox.removeFirst()
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { pump() }

    func close() {
        if let p = peripheral, let st = stateChar, !closed { p.writeValue(MDLBLE.end, for: st, type: .withoutResponse) }
        finish()
    }

    private func finish() {
        guard !closed else { return }
        closed = true
        manager.stopScan()
        if let p = peripheral { manager.cancelPeripheralConnection(p) }
        onClose?()
    }
}

// MARK: - Factories

extension MDLHolderSession {
    /// Starts advertising over Bluetooth for this session's engagement (peripheral server mode).
    func startBluetooth(onError: @escaping (MDLBLEError) -> Void) -> MDLGATTServer? {
        guard let uuid = engagement.peripheralServerUUID else { return nil }
        let server = MDLGATTServer(serviceUUID: uuid, characteristics: MDLBLE.peripheralServer,
                                   ident: MDLBLE.ident(eDeviceKeyBytes: engagement.eDeviceKeyBytes))
        server.onError = onError
        server.onConnected = { [weak self, weak server] in if let server { self?.attach(server) } }
        return server
    }
}

extension MDLReaderSession {
    /// Connects using whichever Bluetooth mode the holder offered (peripheral server preferred).
    func startBluetooth(onError: @escaping (MDLBLEError) -> Void) -> MDLTransport? {
        if let uuid = engagement.peripheralServerUUID {
            let client = MDLGATTClient(serviceUUID: uuid, characteristics: MDLBLE.peripheralServer)
            client.onError = onError
            client.onConnected = { [weak self, weak client] in if let client { self?.start(client) } }
            return client
        }
        if let uuid = engagement.centralClientUUID {
            let server = MDLGATTServer(serviceUUID: uuid, characteristics: MDLBLE.centralClient,
                                       ident: MDLBLE.ident(eDeviceKeyBytes: engagement.eDeviceKeyBytes))
            server.onError = onError
            server.onConnected = { [weak self, weak server] in if let server { self?.start(server) } }
            return server
        }
        return nil
    }
}
