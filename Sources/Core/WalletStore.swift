// SPDX-License-Identifier: GPL-3.0-only
import Foundation

@MainActor
final class WalletStore: ObservableObject {
    static let issuerID = "nz.test.issuer"

    /// DEMO ONLY: the issuer key is generated on the phone so the prototype runs
    /// offline. In production it lives in a government-owned HSM and the wallet
    /// receives credentials via OpenID4VCI.
    private let issuerKey = SoftwareKey()
    let holderKey: any SigningKey = Crypto.makeHolderKey()
    let verifier: Verifier

    @Published private(set) var credentials: [Credential] = []

    // ISO 18013-5 mobile driving licence (in-person sharing over QR + Bluetooth)
    let mdlIssuer = MDLIssuer()
    @Published private(set) var mdoc: IssuedMDoc?
    /// IACA roots this phone trusts when acting as a reader. Other jurisdictions'
    /// roots (e.g. from a VICAL) would be added here by agreement.
    nonisolated static let mdlTrustList: [Data] = [MDLIssuer.iacaPublicKey]
    @Published private(set) var activity: [ActivityEntry] = []

    var holderName: String { credentials.first?.value("fullName") ?? "" }

    /// One immutable snapshot feeds the card, detail views and mDL issuance.
    let appData: SharedAppData
    let portraitJPEG: Data
    let signaturePNG: Data

    init(appData: SharedAppData = .demo) {
        self.appData = appData
        portraitJPEG = DemoLicenceImages.portrait(named: appData.licence.portraitImagePath)
        signaturePNG = DemoLicenceImages.signature(named: appData.licence.signatureImagePath)
        verifier = Verifier(trustRegistry: [Self.issuerID: issuerKey.publicKeyRaw])
        reset()
    }

    /// When the licence was last re-issued / status-checked with the issuer.
    @Published private(set) var lastRefreshed = Date()

    /// Phase 1 (transport authority): driver licence only. Other credential
    /// types stay in `CredentialType` for later phases.
    private func issueLicence() -> Credential {
        // All licence fields come from the single demo-data file (TEST_FILE_ONLY.swift).
        let d = appData.licence
        let over18 = DemoLicenceData.age(d.dateOfBirth) >= 18
        return issue(.driverLicence, claims: [
            ("surname", d.surname), ("firstNames", d.firstNames), ("fullName", d.fullName),
            ("dateOfBirth", d.dateOfBirth), ("licenceNumber", d.licenceNumber), ("cardVersion", d.cardVersion),
            ("licenceClass", d.classesDisplay), ("endorsements", d.endorsementsDisplay), ("conditions", "none"),
            ("donor", d.isOrganDonor ? "true" : "false"), ("demeritPoints", String(d.demeritPoints)),
            ("ageOver18", over18 ? "true" : "false"),
        ], issuedAt: DemoLicenceData.date(d.issueDate), expiresAt: DemoLicenceData.date(d.expiryDate))
    }

    func reset() {
        let now = Date()
        let day: TimeInterval = 86_400
        credentials = [issueLicence()]
        mdoc = issueMDoc()
        lastRefreshed = now
        activity = [
            ActivityEntry(date: now - 2 * day, scenario: .age, credentialType: .driverLicence,
                          sharedClaims: ["ageOver18"], outcomeKey: "activity.shared", positive: true),
            ActivityEntry(date: now - 5 * day, scenario: .identity, credentialType: .driverLicence,
                          sharedClaims: [], outcomeKey: "activity.declined", positive: false),
        ]
    }

    /// Pull-to-refresh: fetch a freshly signed licence and current status.
    /// Mocked locally; in production this calls the issuer over OpenID4VCI.
    func refresh() async {
        try? await Task.sleep(for: .milliseconds(800))
        credentials = [issueLicence()]
        mdoc = issueMDoc()
        lastRefreshed = Date()
    }

    // MARK: mDL (ISO 18013-5)

    /// Issues the mDL with the same licence details, bound to this phone's key.
    func issueMDoc(validUntil: Date? = nil, signer: ((Data) throws -> Data)? = nil) -> IssuedMDoc {
        // All licence fields come from the single demo-data file (TEST_FILE_ONLY.swift).
        let data = appData.licence
        let now = Date(), day: TimeInterval = 86_400
        func fd(_ s: String) -> CBOR { .tagged(1004, .text(s)) }
        let issued = DemoLicenceData.date(data.issueDate)
        let expiry = validUntil ?? DemoLicenceData.date(data.expiryDate)
        // The signed licence data itself is short-lived and refreshed by the wallet; the card's
        // expiry is a separate field. ISO 18013-5 / NSW verifiers require signed ≤ validFrom.
        let msoUntil = validUntil ?? min(expiry, now + 90 * day)
        let privileges = CBOR.array(data.classes.map { c in
            .map([(.text("vehicle_category_code"), .text(c.iso)), (.text("issue_date"), fd(data.issueDate)),
                  (.text("expiry_date"), .fullDate(expiry)),
                  (.text("codes"), .array([.map([(.text("code"), .text("NZ\(c.nzClass)\(c.stage)"))])]))])
        })
        let over18 = DemoLicenceData.age(data.dateOfBirth) >= 18
        let over21 = DemoLicenceData.age(data.dateOfBirth) >= 21
        let iso: [(String, CBOR)] = [
            ("family_name", .text(data.surname.capitalized)), ("given_name", .text(data.firstNames)),
            ("birth_date", fd(data.dateOfBirth)), ("issue_date", .fullDate(issued)), ("expiry_date", .fullDate(expiry)),
            ("issuing_country", .text(data.issuingCountry)), ("issuing_authority", .text(data.issuingAuthority)),
            ("document_number", .text(data.licenceNumber)), ("portrait", .bytes(portraitJPEG)),
            ("driving_privileges", privileges), ("un_distinguishing_sign", .text(data.issuingCountry)),
            ("age_over_18", .bool(over18)), ("age_over_21", .bool(over21)),
        ]
        // NZ fields with no ISO equivalent. Readers in other countries ignore this namespace.
        let nz: [(String, CBOR)] = [
            ("card_version", .text(data.cardVersion)), ("licence_classes", .text(data.classesDisplay)),
            ("endorsements", .array(data.endorsements.map(CBOR.text))), ("organ_donor", .bool(data.isOrganDonor)),
        ]
        return mdlIssuer.issue(elements: [MDL.namespace: iso, MDL.domesticNamespace: nz],
                               deviceKeyX963: holderKey.publicKeyRaw, signed: now,
                               validFrom: now, validUntil: msoUntil, signer: signer)
    }

    /// A new in-person sharing session (fresh QR key and Bluetooth ID each time).
    func makeHolderSession() -> MDLHolderSession? {
        guard let mdoc else { return nil }
        return MDLHolderSession(document: mdoc, deviceSigner: COSE.rawSigner(holderKey))
    }

    func logMDLShare(_ elements: [String], positive: Bool) {
        let scenario = Scenario.allCases.first { Set($0.mdlRequest.elements[MDL.namespace]?.keys.map { $0 } ?? []) == Set(elements) } ?? .identity
        activity.insert(ActivityEntry(date: Date(), scenario: scenario, credentialType: .driverLicence,
                                      sharedClaims: positive ? elements : [],
                                      outcomeKey: positive ? "activity.shared" : "activity.declined",
                                      positive: positive), at: 0)
    }

    // MARK: Issuance (mock issuer)

    func issue(_ type: CredentialType, claims: [(String, String)], issuedAt: Date, expiresAt: Date?,
               signer: (any SigningKey)? = nil) -> Credential {
        let disclosures = claims.map { Disclosure(key: $0.0, value: $0.1, salt: Crypto.random()) }
        let digests = disclosures.map(\.digest).sorted()
        let id = UUID().uuidString.lowercased()
        let key: any SigningKey = signer ?? issuerKey
        let input = Credential.signingInput(id: id, type: type, issuerID: Self.issuerID, issuedAt: issuedAt,
                                            expiresAt: expiresAt, holderKey: holderKey.publicKeyRaw,
                                            digests: digests)
        let sig = (try? key.sign(input)) ?? Data()
        return Credential(id: id, type: type, issuerID: Self.issuerID, issuedAt: issuedAt, expiresAt: expiresAt,
                          holderKey: holderKey.publicKeyRaw, disclosures: disclosures, digests: digests,
                          issuerSignature: sig)
    }

    func issuerSignatureValid(_ c: Credential) -> Bool {
        guard let pk = verifier.trustRegistry[c.issuerID] else { return false }
        return Crypto.verify(signature: c.issuerSignature, data: c.signingInput, publicKeyRaw: pk)
    }

    // MARK: Presentation (wallet side)

    func present(_ c: Credential, claims: [String], nonce: String, verifierID: String) -> Presentation {
        let disclosed = c.disclosures.filter { claims.contains($0.key) }
        let now = Date()
        let input = Presentation.holderInput(credentialID: c.id, nonce: nonce, verifierID: verifierID,
                                             createdAt: now, disclosed: disclosed)
        let sig = (try? holderKey.sign(input)) ?? Data()
        return Presentation(credentialID: c.id, type: c.type, issuerID: c.issuerID, issuedAt: c.issuedAt,
                            expiresAt: c.expiresAt, holderKey: c.holderKey, digests: c.digests,
                            issuerSignature: c.issuerSignature, disclosed: disclosed, nonce: nonce,
                            verifierID: verifierID, createdAt: now, holderSignature: sig)
    }

    // MARK: End-to-end demo (wallet + verifier on one phone)

    func runVerification(request: VerificationRequest, credential: Credential,
                         attack: AttackSimulation, offline: Bool) -> VerificationResult {
        let claims = credential.disclosures.map { ($0.key, $0.value) }
        var cred = credential
        switch attack {
        case .forgedIssuer:
            // Attacker builds a perfect-looking credential but signs it with their own key.
            cred = issue(cred.type, claims: claims, issuedAt: cred.issuedAt, expiresAt: cred.expiresAt,
                         signer: SoftwareKey())
        case .expired:
            cred = issue(cred.type, claims: claims, issuedAt: Date() - 2_000 * 86_400,
                         expiresAt: Date() - 30 * 86_400)
        default: break
        }

        var p = present(cred, claims: request.scenario.requestedClaims, nonce: request.nonce,
                        verifierID: request.scenario.verifierID)

        if attack == .tamperedClaim, let first = p.disclosed.first {
            let edited: String = switch first.value {
            case "true": "false"
            case "false": "true"
            default: "Trần Thị Bích"
            }
            p = p.replacing(disclosed: [Disclosure(key: first.key, value: edited, salt: first.salt)]
                            + p.disclosed.dropFirst())
        }
        if attack == .revoked { verifier.revoked.insert(cred.id) }

        var result = verifier.verify(p, request: request, offline: offline)
        if attack == .replay {
            // Same presentation submitted a second time (e.g. a photographed QR).
            result = verifier.verify(p, request: request, offline: offline)
        }
        if attack == .revoked { verifier.revoked.remove(cred.id) }

        let ok = result.outcome.isPositive
        activity.insert(ActivityEntry(date: Date(), scenario: request.scenario, credentialType: cred.type,
                                      sharedClaims: ok ? request.scenario.requestedClaims : [],
                                      outcomeKey: ok ? "activity.shared" : "activity.rejected",
                                      positive: ok), at: 0)
        return result
    }

    func logDeclined(_ request: VerificationRequest, type: CredentialType) {
        activity.insert(ActivityEntry(date: Date(), scenario: request.scenario, credentialType: type,
                                      sharedClaims: [], outcomeKey: "activity.declined", positive: false), at: 0)
    }
}

extension VerificationOutcome {
    var isPositive: Bool {
        switch self {
        case .valid, .validOffline: true
        default: false
        }
    }
}
