// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Minimal CBOR (RFC 8949) used by ISO/IEC 18013-5. Written for this project.
/// Maps keep insertion order; we always sign and digest the exact bytes we send
/// or receive (tag 24 wrappers), so key order never affects verification.
struct CBORPair: Hashable {
    var key: CBOR
    var value: CBOR
}

indirect enum CBOR: Hashable {
    case unsigned(UInt64)
    case negative(UInt64)          // value is -1 - n
    case bytes(Data)
    case text(String)
    case array([CBOR])
    case map([CBORPair])
    case tagged(UInt64, CBOR)
    case bool(Bool)
    case null
    case undefined
    case double(Double)

    // MARK: Convenience constructors

    static func int(_ i: Int) -> CBOR { i >= 0 ? .unsigned(UInt64(i)) : .negative(UInt64(-1 - i)) }
    static func map(_ pairs: [(CBOR, CBOR)]) -> CBOR { .map(pairs.map { CBORPair(key: $0.0, value: $0.1) }) }

    /// `#6.24(bstr .cbor x)`: an embedded, separately encoded CBOR item.
    static func embedded(_ item: CBOR) -> CBOR { .tagged(24, .bytes(item.encoded())) }
    static func embeddedBytes(_ raw: Data) -> CBOR { .tagged(24, .bytes(raw)) }

    /// ISO 18013-5 tdate (tag 0) and full-date (tag 1004).
    static func tdate(_ d: Date) -> CBOR { .tagged(0, .text(CBORDate.tdate.string(from: d))) }
    /// Calendar date as seen by the issuer (no time zone shift for the holder or reader).
    static func fullDate(_ d: Date, in tz: TimeZone = .current) -> CBOR {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = tz; f.dateFormat = "yyyy-MM-dd"
        return .tagged(1004, .text(f.string(from: d)))
    }

    // MARK: Accessors

    var int: Int? {
        switch self {
        case .unsigned(let u): return u <= UInt64(Int.max) ? Int(u) : nil
        case .negative(let n): return n < UInt64(Int.max) ? -1 - Int(n) : nil
        default: return nil
        }
    }
    var text: String? { if case .text(let s) = self { s } else { nil } }
    var bytes: Data? { if case .bytes(let d) = self { d } else { nil } }
    var array: [CBOR]? { if case .array(let a) = self { a } else { nil } }
    var pairs: [CBORPair]? { if case .map(let m) = self { m } else { nil } }
    var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
    var isNull: Bool { if case .null = self { true } else { false } }

    /// Content of a tag (any tag number); the item itself if untagged.
    var untagged: CBOR { if case .tagged(_, let v) = self { v.untagged } else { self } }
    /// Raw bytes inside `#6.24(bstr)`.
    var embeddedRaw: Data? { if case .tagged(24, .bytes(let d)) = self { d } else { nil } }

    subscript(key: String) -> CBOR? { pairs?.first { $0.key == .text(key) }?.value }
    subscript(key: Int) -> CBOR? { pairs?.first { $0.key == .int(key) }?.value }

    /// Dates as found in mDL elements: tag 1004, tag 0 or plain text.
    /// "dd/MM/yyyy" for a full-date or tdate, read as written (no time zone conversion).
    var displayDate: String? {
        guard case .text(let s) = untagged, s.count >= 10 else { return nil }
        let p = s.prefix(10).split(separator: "-")
        guard p.count == 3, p[0].count == 4, p.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return "\(p[2])/\(p[1])/\(p[0])"
    }

    var date: Date? {
        guard case .text(let s) = untagged else { return nil }
        return CBORDate.fullDate.date(from: s) ?? CBORDate.tdate.date(from: s)
            ?? CBORDate.tdateFraction.date(from: s)
    }
}

enum CBORDate {
    private static func f(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = pattern
        return f
    }
    static let tdate = f("yyyy-MM-dd'T'HH:mm:ss'Z'")
    static let tdateFraction = f("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
    static let fullDate = f("yyyy-MM-dd")
}

// MARK: - Encoding

extension CBOR {
    func encoded() -> Data {
        var out = Data()
        encode(into: &out)
        return out
    }

    private static func head(_ major: UInt8, _ value: UInt64, into out: inout Data) {
        let m = major << 5
        switch value {
        case ..<24: out.append(m | UInt8(value))
        case ..<0x100: out.append(m | 24); out.append(UInt8(value))
        case ..<0x10000: out.append(m | 25); out.append(contentsOf: withUnsafeBytes(of: UInt16(value).bigEndian, Array.init))
        case ..<0x1_0000_0000: out.append(m | 26); out.append(contentsOf: withUnsafeBytes(of: UInt32(value).bigEndian, Array.init))
        default: out.append(m | 27); out.append(contentsOf: withUnsafeBytes(of: value.bigEndian, Array.init))
        }
    }

    private func encode(into out: inout Data) {
        switch self {
        case .unsigned(let u): Self.head(0, u, into: &out)
        case .negative(let n): Self.head(1, n, into: &out)
        case .bytes(let d): Self.head(2, UInt64(d.count), into: &out); out.append(d)
        case .text(let s): let d = Data(s.utf8); Self.head(3, UInt64(d.count), into: &out); out.append(d)
        case .array(let a): Self.head(4, UInt64(a.count), into: &out); a.forEach { $0.encode(into: &out) }
        case .map(let m):
            Self.head(5, UInt64(m.count), into: &out)
            m.forEach { $0.key.encode(into: &out); $0.value.encode(into: &out) }
        case .tagged(let t, let v): Self.head(6, t, into: &out); v.encode(into: &out)
        case .bool(let b): out.append(b ? 0xF5 : 0xF4)
        case .null: out.append(0xF6)
        case .undefined: out.append(0xF7)
        case .double(let d): out.append(0xFB); out.append(contentsOf: withUnsafeBytes(of: d.bitPattern.bigEndian, Array.init))
        }
    }
}

// MARK: - Decoding

enum CBORError: Error { case truncated, malformed, trailingBytes, tooDeep }

extension CBOR {
    static func decode(_ data: Data) throws -> CBOR {
        var r = Reader(bytes: [UInt8](data))
        let v = try r.item(depth: 0)
        guard r.pos == r.bytes.count else { throw CBORError.trailingBytes }
        return v
    }

    private struct Reader {
        let bytes: [UInt8]
        var pos = 0

        mutating func byte() throws -> UInt8 {
            guard pos < bytes.count else { throw CBORError.truncated }
            defer { pos += 1 }
            return bytes[pos]
        }
        mutating func take(_ n: Int) throws -> [UInt8] {
            guard n >= 0, pos + n <= bytes.count else { throw CBORError.truncated }
            defer { pos += n }
            return Array(bytes[pos..<pos + n])
        }
        mutating func uint(_ n: Int) throws -> UInt64 {
            try take(n).reduce(0) { $0 << 8 | UInt64($1) }
        }
        /// Returns nil for indefinite length (additional info 31).
        mutating func argument(_ info: UInt8) throws -> UInt64? {
            switch info {
            case ..<24: return UInt64(info)
            case 24: return try uint(1)
            case 25: return try uint(2)
            case 26: return try uint(4)
            case 27: return try uint(8)
            case 31: return nil
            default: throw CBORError.malformed
            }
        }
        mutating func isBreak() -> Bool {
            if pos < bytes.count, bytes[pos] == 0xFF { pos += 1; return true }
            return false
        }

        mutating func item(depth: Int) throws -> CBOR {
            guard depth < 64 else { throw CBORError.tooDeep }
            let ib = try byte()
            let major = ib >> 5, info = ib & 0x1F
            switch major {
            case 0: guard let v = try argument(info) else { throw CBORError.malformed }; return .unsigned(v)
            case 1: guard let v = try argument(info) else { throw CBORError.malformed }; return .negative(v)
            case 2, 3:
                var chunk = [UInt8]()
                if let n = try argument(info) {
                    guard n < UInt64(bytes.count) + 1 else { throw CBORError.truncated }
                    chunk = try take(Int(n))
                } else {
                    while !isBreak() {
                        let part = try item(depth: depth + 1)
                        let d: Data? = major == 2 ? part.bytes : part.text.map { Data($0.utf8) }
                        guard let d else { throw CBORError.malformed }
                        chunk += [UInt8](d)
                    }
                }
                if major == 2 { return .bytes(Data(chunk)) }
                guard let s = String(bytes: chunk, encoding: .utf8) else { throw CBORError.malformed }
                return .text(s)
            case 4:
                var a = [CBOR]()
                if let n = try argument(info) {
                    guard n < UInt64(bytes.count) + 1 else { throw CBORError.truncated }
                    for _ in 0..<n { a.append(try item(depth: depth + 1)) }
                } else {
                    while !isBreak() { a.append(try item(depth: depth + 1)) }
                }
                return .array(a)
            case 5:
                var m = [CBORPair]()
                if let n = try argument(info) {
                    guard n < UInt64(bytes.count) + 1 else { throw CBORError.truncated }
                    for _ in 0..<n { m.append(CBORPair(key: try item(depth: depth + 1), value: try item(depth: depth + 1))) }
                } else {
                    while !isBreak() { m.append(CBORPair(key: try item(depth: depth + 1), value: try item(depth: depth + 1))) }
                }
                return .map(m)
            case 6:
                guard let t = try argument(info) else { throw CBORError.malformed }
                return .tagged(t, try item(depth: depth + 1))
            default:
                switch info {
                case 20: return .bool(false)
                case 21: return .bool(true)
                case 22: return .null
                case 23: return .undefined
                case 25: return .double(Double(Self.half(UInt16(try uint(2)))))
                case 26: return .double(Double(Float(bitPattern: UInt32(try uint(4)))))
                case 27: return .double(Double(bitPattern: try uint(8)))
                default:
                    if info < 20 { return .unsigned(UInt64(info)) }   // unassigned simple value
                    throw CBORError.malformed
                }
            }
        }

        static func half(_ h: UInt16) -> Float {
            let exp = Int((h >> 10) & 0x1F), mant = Float(h & 0x3FF)
            let sign: Float = (h & 0x8000) != 0 ? -1 : 1
            if exp == 0 { return sign * mant * pow(2, -24) }
            if exp == 31 { return mant == 0 ? sign * .infinity : .nan }
            return sign * (1 + mant / 1024) * pow(2, Float(exp - 15))
        }
    }
}

extension Data {
    /// base64url without padding (RFC 4648 §5), as used in `mdoc:` QR codes.
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    init?(base64URL s: String) {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        self.init(base64Encoded: b)
    }
}
