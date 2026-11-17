// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The five outcomes a verifier can show (RFP §4.2 + §9 offline rule).
enum VerificationOutcome {
    case valid
    case validOffline(Date)       // status list is cached, not live
    case invalid(String)          // reason localisation key
    case expired
    case unverifiable(String)
}

struct VerificationCheck: Identifiable {
    let id = UUID()
    let labelKey: String
    let passed: Bool
}

struct VerificationResult {
    let outcome: VerificationOutcome
    let disclosed: [Disclosure]
    let checks: [VerificationCheck]
}

/// Verifier logic. In production this is the shared (Rust) core used by the
/// verifier app, the verification gateway and the Android wallet.
final class Verifier {
    /// Trust registry: issuer ID → issuer public key.
    var trustRegistry: [String: Data]
    /// Revocation/suspension status list (cached copy for offline use).
    var revoked: Set<String> = []
    var statusListFetchedAt = Date().addingTimeInterval(-3 * 3600)
    private var usedNonces: Set<String> = []
    let maxAge: TimeInterval = 120

    init(trustRegistry: [String: Data]) { self.trustRegistry = trustRegistry }

    func verify(_ p: Presentation, request: VerificationRequest, offline: Bool,
                now: Date = .now) -> VerificationResult {
        var checks: [VerificationCheck] = []
        func pass(_ k: String) { checks.append(.init(labelKey: k, passed: true)) }
        func fail(_ k: String, _ o: VerificationOutcome) -> VerificationResult {
            checks.append(.init(labelKey: k, passed: false))
            return VerificationResult(outcome: o, disclosed: [], checks: checks)
        }

        // 1. Issuer is trusted
        guard let issuerKey = trustRegistry[p.issuerID] else {
            return fail("check.trustedIssuer", .unverifiable("reason.untrustedIssuer"))
        }
        pass("check.trustedIssuer")

        // 2. Issuer signature over the salted digests
        let input = Credential.signingInput(id: p.credentialID, type: p.type, issuerID: p.issuerID,
                                            issuedAt: p.issuedAt, expiresAt: p.expiresAt,
                                            holderKey: p.holderKey, digests: p.digests)
        guard Crypto.verify(signature: p.issuerSignature, data: input, publicKeyRaw: issuerKey) else {
            return fail("check.issuerSignature", .invalid("reason.badIssuerSig"))
        }
        pass("check.issuerSignature")

        // 3. Every disclosed value hashes to a digest the issuer signed
        let signed = Set(p.digests)
        guard p.disclosed.allSatisfy({ signed.contains($0.digest) }) else {
            return fail("check.integrity", .invalid("reason.tampered"))
        }
        pass("check.integrity")

        // 4. Holder binding: presentation signed by the device key in the credential
        let hInput = Presentation.holderInput(credentialID: p.credentialID, nonce: p.nonce,
                                              verifierID: p.verifierID, createdAt: p.createdAt,
                                              disclosed: p.disclosed)
        guard Crypto.verify(signature: p.holderSignature, data: hInput, publicKeyRaw: p.holderKey) else {
            return fail("check.deviceBinding", .invalid("reason.badHolderSig"))
        }
        pass("check.deviceBinding")

        // 5. Challenge-response: our nonce, never seen before
        guard p.nonce == request.nonce, p.verifierID == request.scenario.verifierID,
              !usedNonces.contains(p.nonce) else {
            return fail("check.nonce", .invalid("reason.replay"))
        }
        usedNonces.insert(p.nonce)
        pass("check.nonce")

        // 6. Freshness
        guard abs(now.timeIntervalSince(p.createdAt)) <= maxAge else {
            return fail("check.freshness", .invalid("reason.stale"))
        }
        pass("check.freshness")

        // 7. Everything we asked for is present
        let got = Set(p.disclosed.map(\.key))
        guard request.scenario.requestedClaims.allSatisfy(got.contains) else {
            return fail("check.requested", .invalid("reason.missingClaims"))
        }
        pass("check.requested")

        // 8. Expiry
        if let exp = p.expiresAt, exp < now { return fail("check.expiry", .expired) }
        pass("check.expiry")

        // 9. Revocation status
        let statusKey = offline ? "check.statusOffline" : "check.status"
        guard !revoked.contains(p.credentialID) else {
            return fail(statusKey, .invalid("reason.revoked"))
        }
        pass(statusKey)

        if offline {
            return VerificationResult(outcome: .validOffline(statusListFetchedAt), disclosed: p.disclosed, checks: checks)
        }
        return VerificationResult(outcome: .valid, disclosed: p.disclosed, checks: checks)
    }
}
