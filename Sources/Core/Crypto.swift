// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit
import Security

/// A key that can sign. Issuer keys live in government HSMs in production;
/// holder (citizen) keys live in the Secure Enclave and never leave the phone.
protocol SigningKey {
    var publicKeyRaw: Data { get }
    var isHardwareBacked: Bool { get }
    func sign(_ data: Data) throws -> Data
}

struct SoftwareKey: SigningKey {
    private let key = P256.Signing.PrivateKey()
    var publicKeyRaw: Data { key.publicKey.x963Representation }
    var isHardwareBacked: Bool { false }
    func sign(_ data: Data) throws -> Data { try key.signature(for: data).derRepresentation }
}

struct SecureEnclaveKey: SigningKey {
    private let key: SecureEnclave.P256.Signing.PrivateKey
    init() throws { key = try SecureEnclave.P256.Signing.PrivateKey() }
    var publicKeyRaw: Data { key.publicKey.x963Representation }
    var isHardwareBacked: Bool { true }
    func sign(_ data: Data) throws -> Data { try key.signature(for: data).derRepresentation }
}

enum Crypto {
    /// Secure Enclave on real devices; software fallback in the Simulator.
    static func makeHolderKey() -> any SigningKey {
        if SecureEnclave.isAvailable, let key = try? SecureEnclaveKey() { return key }
        return SoftwareKey()
    }

    static func verify(signature: Data, data: Data, publicKeyRaw: Data) -> Bool {
        guard let pk = try? P256.Signing.PublicKey(x963Representation: publicKeyRaw),
              let sig = try? P256.Signing.ECDSASignature(derRepresentation: signature) else { return false }
        return pk.isValidSignature(sig, for: data)
    }

    static func digest(_ s: String) -> String {
        Data(SHA256.hash(data: Data(s.utf8))).base64EncodedString()
    }

    static func random(_ bytes: Int = 16) -> String {
        var b = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &b)
        return Data(b).base64EncodedString()
    }
}
