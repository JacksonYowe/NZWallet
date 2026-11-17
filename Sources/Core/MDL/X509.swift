// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import CryptoKit

/// Just enough X.509 (DER) for 18013-5: build the demo IACA root and
/// document-signer certificates, and parse/verify the chain on the reader.
/// Production certificates come from the national PKI, not from this code.
enum DER {
    static func tlv(_ tag: UInt8, _ body: Data) -> Data {
        var out = Data([tag])
        let n = body.count
        if n < 0x80 { out.append(UInt8(n)) }
        else if n < 0x100 { out += [0x81, UInt8(n)] }
        else if n < 0x10000 { out += [0x82, UInt8(n >> 8), UInt8(n & 0xFF)] }
        else { out += [0x83, UInt8(n >> 16), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] }
        return out + body
    }
    static func seq(_ items: Data...) -> Data { tlv(0x30, items.reduce(Data(), +)) }
    static func set(_ items: Data...) -> Data { tlv(0x31, items.reduce(Data(), +)) }
    static func int(_ v: Data) -> Data {
        var b = [UInt8](v)
        while b.count > 1, b[0] == 0, b[1] < 0x80 { b.removeFirst() }
        if let f = b.first, f >= 0x80 { b.insert(0, at: 0) }
        return tlv(0x02, Data(b))
    }
    static func int(_ v: Int) -> Data { int(withUnsafeBytes(of: UInt64(v).bigEndian) { Data($0) }) }
    static func bool(_ v: Bool) -> Data { tlv(0x01, Data([v ? 0xFF : 0])) }
    static func octets(_ d: Data) -> Data { tlv(0x04, d) }
    static func bits(_ d: Data, unused: UInt8 = 0) -> Data { tlv(0x03, Data([unused]) + d) }
    static func utf8(_ s: String) -> Data { tlv(0x0C, Data(s.utf8)) }
    static func printable(_ s: String) -> Data { tlv(0x13, Data(s.utf8)) }
    static func explicit(_ n: UInt8, _ d: Data) -> Data { tlv(0xA0 | n, d) }
    static func oid(_ s: String) -> Data {
        let parts = s.split(separator: ".").compactMap { UInt64($0) }
        var body = [UInt8(parts[0] * 40 + parts[1])]
        for p in parts.dropFirst(2) {
            var stack = [UInt8(p & 0x7F)]
            var v = p >> 7
            while v > 0 { stack.insert(UInt8(v & 0x7F) | 0x80, at: 0); v >>= 7 }
            body += stack
        }
        return tlv(0x06, Data(body))
    }
    static func time(_ d: Date) -> Data {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        let year = Calendar(identifier: .gregorian).component(.year, from: d)
        if year < 2050 { f.dateFormat = "yyMMddHHmmss'Z'"; return tlv(0x17, Data(f.string(from: d).utf8)) }
        f.dateFormat = "yyyyMMddHHmmss'Z'"; return tlv(0x18, Data(f.string(from: d).utf8))
    }

    // MARK: Parsing

    struct Node {
        let tag: UInt8
        let raw: Data        // full TLV
        let body: Data
        var children: [Node] { (try? DER.parseAll(body)) ?? [] }
    }

    static func parse(_ d: Data) throws -> (Node, Int) {
        let b = [UInt8](d)
        guard b.count >= 2 else { throw CBORError.truncated }
        var i = 1, len = Int(b[1])
        if b[1] & 0x80 != 0 {
            let n = Int(b[1] & 0x7F)
            guard n <= 3, b.count >= 2 + n else { throw CBORError.malformed }
            len = b[2..<2 + n].reduce(0) { $0 << 8 | Int($1) }
            i += n
        }
        i += 1
        guard b.count >= i + len else { throw CBORError.truncated }
        let start = d.startIndex
        return (Node(tag: b[0], raw: d.subdata(in: start..<start + i + len),
                     body: d.subdata(in: start + i..<start + i + len)), i + len)
    }

    static func parseAll(_ d: Data) throws -> [Node] {
        var out = [Node](), rest = d
        while !rest.isEmpty {
            let (n, used) = try parse(rest)
            out.append(n)
            rest = rest.subdata(in: rest.startIndex + used..<rest.endIndex)
        }
        return out
    }
}

enum X509 {
    static let ecdsaSHA256 = "1.2.840.10045.4.3.2"
    static let ecPublicKey = "1.2.840.10045.2.1"
    static let prime256v1 = "1.2.840.10045.3.1.7"
    static let mdlDSExtKeyUsage = "1.0.18013.5.1.2"

    struct Name { var country: String; var commonName: String }

    private static func name(_ n: Name) -> Data {
        DER.seq(DER.set(DER.seq(DER.oid("2.5.4.6"), DER.printable(n.country))),
                DER.set(DER.seq(DER.oid("2.5.4.3"), DER.utf8(n.commonName))))
    }

    private static func ext(_ oid: String, critical: Bool, _ value: Data) -> Data {
        critical ? DER.seq(DER.oid(oid), DER.bool(true), DER.octets(value)) : DER.seq(DER.oid(oid), DER.octets(value))
    }

    private static func keyID(_ x963: Data) -> Data { Data(Insecure.SHA1.hash(data: x963)) }

    /// Builds a certificate. `isCA` makes an IACA root; otherwise a document signer.
    static func certificate(subject: Name, issuer: Name, subjectKey: Data, issuerKeyX963: Data,
                            serial: Int, notBefore: Date, notAfter: Date, isCA: Bool,
                            signer: P256.Signing.PrivateKey) throws -> Data {
        let alg = DER.seq(DER.oid(ecdsaSHA256))
        let spki = DER.seq(DER.seq(DER.oid(ecPublicKey), DER.oid(prime256v1)), DER.bits(subjectKey))
        var exts = Data()
        if isCA {
            exts += ext("2.5.29.19", critical: true, DER.seq(DER.bool(true), DER.int(0)))
            exts += ext("2.5.29.15", critical: true, DER.bits(Data([0x06]), unused: 1))     // keyCertSign, cRLSign
        } else {
            exts += ext("2.5.29.15", critical: true, DER.bits(Data([0x80]), unused: 7))     // digitalSignature
            exts += ext("2.5.29.37", critical: true, DER.seq(DER.oid(mdlDSExtKeyUsage)))
            exts += ext("2.5.29.35", critical: false, DER.seq(DER.tlv(0x80, keyID(issuerKeyX963))))
        }
        exts += ext("2.5.29.14", critical: false, DER.octets(keyID(subjectKey)))
        let tbs = DER.seq(DER.explicit(0, DER.int(2)), DER.int(serial), alg, name(issuer),
                          DER.seq(DER.time(notBefore), DER.time(notAfter)), name(subject), spki,
                          DER.explicit(3, DER.seq(exts)))
        let sig = try signer.signature(for: tbs).derRepresentation
        return DER.seq(tbs, alg, DER.bits(sig))
    }

    /// The parts of a certificate the reader needs.
    struct Parsed {
        let tbs: Data
        let signatureDER: Data
        let publicKeyX963: Data
        let notBefore: Date?
        let notAfter: Date?
        let subjectCN: String?
        let country: String?

        init(_ der: Data) throws {
            let (cert, _) = try DER.parse(der)
            let top = cert.children
            guard top.count == 3 else { throw CBORError.malformed }
            tbs = top[0].raw
            signatureDER = Data(top[2].body.dropFirst())
            var t = top[0].children
            if t.first?.tag == 0xA0 { t.removeFirst() }               // version
            guard t.count >= 6 else { throw CBORError.malformed }
            let validity = t[3].children
            notBefore = validity.first.flatMap(X509.time)
            notAfter = validity.dropFirst().first.flatMap(X509.time)
            let attrs = t[4].children.flatMap(\.children).map(\.children)
            func attr(_ oid: String) -> String? {
                attrs.first { $0.first?.raw == DER.oid(oid) }.flatMap { String(data: $0[1].body, encoding: .utf8) }
            }
            subjectCN = attr("2.5.4.3"); country = attr("2.5.4.6")
            let key = t[5].children
            guard key.count == 2 else { throw CBORError.malformed }
            publicKeyX963 = Data(key[1].body.dropFirst())
        }

        func isSigned(byX963 issuerKey: Data) -> Bool {
            guard let pk = try? P256.Signing.PublicKey(x963Representation: issuerKey),
                  let sig = try? P256.Signing.ECDSASignature(derRepresentation: signatureDER) else { return false }
            return pk.isValidSignature(sig, for: tbs)
        }

        func isValid(at d: Date) -> Bool {
            guard let a = notBefore, let b = notAfter else { return false }
            return a <= d && d <= b
        }
    }

    fileprivate static func time(_ n: DER.Node) -> Date? {
        guard let s = String(data: n.body, encoding: .ascii) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = n.tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return f.date(from: s)
    }
}
