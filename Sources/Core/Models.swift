// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum CredentialType: String, Codable, CaseIterable, Identifiable {
    case nationalID, driverLicence, healthInsurance, degree
    var id: String { rawValue }
    var titleKey: String { "cred.\(rawValue)" }
    var issuerNameKey: String { "issuer.\(rawValue)" }
    var primaryClaim: String {
        switch self {
        case .nationalID: "idNumber"
        case .driverLicence: "licenceNumber"
        case .healthInsurance: "insuranceNumber"
        case .degree: "qualification"
        }
    }
}

/// One claim plus its random salt. Only the salted hash goes into the signed
/// credential, so the holder can reveal claims one at a time (SD-JWT style).
struct Disclosure: Codable, Hashable {
    let key: String
    let value: String
    let salt: String
    var digest: String { Crypto.digest("\(salt)|\(key)|\(value)") }
}

struct Credential: Identifiable, Codable {
    let id: String
    let type: CredentialType
    let issuerID: String
    let issuedAt: Date
    let expiresAt: Date?
    let holderKey: Data            // device public key this credential is bound to
    let disclosures: [Disclosure]  // private to the wallet
    let digests: [String]          // signed by the issuer
    let issuerSignature: Data

    func value(_ key: String) -> String? { disclosures.first { $0.key == key }?.value }

    static func signingInput(id: String, type: CredentialType, issuerID: String, issuedAt: Date,
                             expiresAt: Date?, holderKey: Data, digests: [String]) -> Data {
        let parts = [id, type.rawValue, issuerID,
                     String(Int(issuedAt.timeIntervalSince1970)),
                     String(Int(expiresAt?.timeIntervalSince1970 ?? 0)),
                     holderKey.base64EncodedString()] + digests.sorted()
        return Data(parts.joined(separator: "\n").utf8)
    }

    var signingInput: Data {
        Self.signingInput(id: id, type: type, issuerID: issuerID, issuedAt: issuedAt,
                          expiresAt: expiresAt, holderKey: holderKey, digests: digests)
    }
}

enum CredentialStatus {
    case valid, expiringSoon(Int), expired
}

extension Credential {
    func status(now: Date = .now) -> CredentialStatus {
        guard let exp = expiresAt else { return .valid }
        if exp < now { return .expired }
        let days = Calendar.current.dateComponents([.day], from: now, to: exp).day ?? 0
        return days <= 30 ? .expiringSoon(max(days, 0)) : .valid
    }
}

/// What the wallet sends to a verifier: the signed credential, only the chosen
/// disclosures, and a device signature over the verifier's fresh nonce.
struct Presentation: Codable {
    let credentialID: String
    let type: CredentialType
    let issuerID: String
    let issuedAt: Date
    let expiresAt: Date?
    let holderKey: Data
    let digests: [String]
    let issuerSignature: Data
    let disclosed: [Disclosure]
    let nonce: String
    let verifierID: String
    let createdAt: Date
    let holderSignature: Data

    static func holderInput(credentialID: String, nonce: String, verifierID: String,
                            createdAt: Date, disclosed: [Disclosure]) -> Data {
        let parts = [credentialID, nonce, verifierID, String(Int(createdAt.timeIntervalSince1970))]
            + disclosed.map(\.digest).sorted()
        return Data(parts.joined(separator: "\n").utf8)
    }

    func replacing(disclosed newDisclosed: [Disclosure]) -> Presentation {
        Presentation(credentialID: credentialID, type: type, issuerID: issuerID, issuedAt: issuedAt,
                     expiresAt: expiresAt, holderKey: holderKey, digests: digests,
                     issuerSignature: issuerSignature, disclosed: newDisclosed, nonce: nonce,
                     verifierID: verifierID, createdAt: createdAt, holderSignature: holderSignature)
    }

    var qrPayload: String {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        return (try? enc.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}

enum Scenario: String, Codable, CaseIterable, Identifiable {
    case age, identity, driver
    var id: String { rawValue }
    var titleKey: String { "scenario.\(rawValue)" }
    var verifierNameKey: String { "verifier.\(rawValue)" }
    var purposeKey: String { "purpose.\(rawValue)" }
    var verifierID: String { "nz.test.verifier.\(rawValue)" }
    var icon: String {
        switch self {
        case .age: "cart.fill"
        case .identity: "building.columns.fill"
        case .driver: "car.fill"
        }
    }
    var acceptedTypes: [CredentialType] {
        switch self {
        case .age, .identity, .driver: [.driverLicence]
        }
    }
    var requestedClaims: [String] {
        switch self {
        case .age: ["ageOver18"]
        case .identity: ["fullName", "dateOfBirth", "licenceNumber", "cardVersion"]
        case .driver: ["fullName", "licenceNumber", "licenceClass", "conditions"]
        }
    }
}

struct VerificationRequest: Identifiable {
    let id = UUID()
    let scenario: Scenario
    var attack: AttackSimulation = .none   // demo only
    var offline = false
    let nonce = Crypto.random()
    let createdAt = Date()

    var qrPayload: String {
        let obj: [String: Any] = ["v": 1, "verifier": scenario.verifierID, "nonce": nonce,
                                  "claims": scenario.requestedClaims,
                                  "ts": Int(createdAt.timeIntervalSince1970)]
        let data = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

enum AttackSimulation: String, CaseIterable, Identifiable {
    case none, tamperedClaim, forgedIssuer, replay, revoked, expired
    var id: String { rawValue }
    var titleKey: String { "attack.\(rawValue)" }
}

struct ActivityEntry: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let scenario: Scenario
    let credentialType: CredentialType
    let sharedClaims: [String]
    let outcomeKey: String
    let positive: Bool
}

/// Invalidates any in-flight unlock when the app leaves the foreground.
struct AppLockState {
    private(set) var isUnlocked = false
    private(set) var generation: UInt = 0

    mutating func lock() {
        isUnlocked = false
        generation &+= 1
    }

    mutating func unlock(ifGenerationMatches expected: UInt) {
        guard expected == generation else { return }
        isUnlocked = true
    }
}

/// Relative attitude in radians -> smoothed foil input; 40 degrees reaches an edge.
struct FoilTiltResponse {
    private(set) var x = 0.0
    private(set) var y = 0.0

    mutating func update(roll: Double, pitch: Double) {
        guard roll.isFinite, pitch.isFinite else { return }
        let range = Double.pi / 4.5
        x += (max(-1, min(1, roll / range)) - x) * 0.18
        y += (max(-1, min(1, pitch / range)) - y) * 0.18
    }
}

/// Deterministic fade sequence, independent of cancellable view animation tasks.
enum CardStarCycle {
    static let duration = 6.8
    static func opacity(index: Int, elapsed: TimeInterval) -> Double {
        let phase = max(0, elapsed).truncatingRemainder(dividingBy: duration) / 2
        let out = 0.25 + Double(index) * 0.18
        let back = 1.15 + Double(index) * 0.18
        if phase < out { return 1 }
        if phase < out + 0.16 { return 1 - (phase - out) / 0.16 }
        if phase < back { return 0 }
        if phase < back + 0.16 { return (phase - back) / 0.16 }
        return 1
    }
}
