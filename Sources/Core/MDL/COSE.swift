// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// COSE (RFC 9052) pieces used by ISO/IEC 18013-5: EC2 keys on P-256 and
/// COSE_Sign1 with ES256. Signatures are raw r||s (64 bytes).
enum COSE {
    static let algES256 = -7
    static let headerAlg = 1
    static let headerX5Chain = 33

    // MARK: Keys

    /// COSE_Key {1: 2 (EC2), -1: 1 (P-256), -2: x, -3: y} from an X9.63 public key (04||x||y).
    static func key(x963 raw: Data) -> CBOR {
        let b = [UInt8](raw)
        precondition(b.count == 65 && b[0] == 4, "expected uncompressed P-256 point")
        return .map([(.int(1), .int(2)), (.int(-1), .int(1)),
                     (.int(-2), .bytes(Data(b[1...32]))), (.int(-3), .bytes(Data(b[33...64])))])
    }

    static func x963(fromKey k: CBOR) -> Data? {
        guard k[1]?.int == 2, k[-1]?.int == 1, let x = k[-2]?.bytes, let y = k[-3]?.bytes,
              x.count == 32, y.count == 32 else { return nil }
        return Data([4]) + x + y
    }

    // MARK: Sign1

    struct Sign1 {
        var protected: Data          // encoded protected header map, exactly as received
        var unprotected: CBOR
        var payload: Data?           // nil when detached
        var signature: Data

        var cbor: CBOR {
            .array([.bytes(protected), unprotected, payload.map(CBOR.bytes) ?? .null, .bytes(signature)])
        }

        init(protected: Data, unprotected: CBOR, payload: Data?, signature: Data) {
            self.protected = protected; self.unprotected = unprotected
            self.payload = payload; self.signature = signature
        }

        init?(_ c: CBOR) {
            guard let a = c.untagged.array, a.count == 4, let p = a[0].bytes, let sig = a[3].bytes else { return nil }
            protected = p; unprotected = a[1]; payload = a[2].bytes; signature = sig
        }

        var algorithm: Int? { (try? CBOR.decode(protected))?[COSE.headerAlg]?.int }

        /// Certificates from the x5chain header (single bstr or array of bstr).
        var x5chain: [Data] {
            guard let v = unprotected[COSE.headerX5Chain] ?? (try? CBOR.decode(protected))?[COSE.headerX5Chain] else { return [] }
            if let d = v.bytes { return [d] }
            return v.array?.compactMap(\.bytes) ?? []
        }

        static func toBeSigned(protected: Data, payload: Data) -> Data {
            CBOR.array([.text("Signature1"), .bytes(protected), .bytes(Data()), .bytes(payload)]).encoded()
        }

        /// Signs with a P-256 key. `detached` leaves the payload out of the structure.
        static func sign(payload: Data, detached: Bool = false, x5chain: [Data] = [],
                         signer: (Data) throws -> Data) rethrows -> Sign1 {
            let prot = CBOR.map([(.int(COSE.headerAlg), .int(COSE.algES256))]).encoded()
            let unprot: CBOR = x5chain.isEmpty ? .map([CBORPair]()) :
                .map([(.int(COSE.headerX5Chain), x5chain.count == 1 ? .bytes(x5chain[0]) : .array(x5chain.map(CBOR.bytes)))])
            let sig = try signer(toBeSigned(protected: prot, payload: payload))
            return Sign1(protected: prot, unprotected: unprot, payload: detached ? nil : payload, signature: sig)
        }

        /// Verifies ES256. Pass `detachedPayload` when the payload was not included.
        func verify(publicKeyX963: Data, detachedPayload: Data? = nil) -> Bool {
            guard algorithm == COSE.algES256, let body = detachedPayload ?? payload,
                  let pk = try? P256.Signing.PublicKey(x963Representation: publicKeyX963),
                  let sig = try? P256.Signing.ECDSASignature(rawRepresentation: signature) else { return false }
            return pk.isValidSignature(sig, for: Self.toBeSigned(protected: protected, payload: body))
        }
    }

    /// Adapts a DER-signing key (Secure Enclave or software) to raw COSE signatures.
    static func rawSigner(_ key: any SigningKey) -> (Data) throws -> Data {
        { data in try P256.Signing.ECDSASignature(derRepresentation: key.sign(data)).rawRepresentation }
    }
    static func rawSigner(_ key: P256.Signing.PrivateKey) -> (Data) throws -> Data {
        { data in try key.signature(for: data).rawRepresentation }
    }
}
