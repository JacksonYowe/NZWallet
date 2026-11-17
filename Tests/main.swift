// SPDX-License-Identifier: GPL-3.0-only
// Headless check of the credential crypto + verifier logic.
// Run:  ./Tests/run.sh
import Foundation
import ImageIO

@MainActor func run() -> Bool {
    let store = WalletStore()
    var allOK = true
    var tilt = FoilTiltResponse()
    tilt.update(roll: 0.08, pitch: -0.10)
    let smallTiltWorks = tilt.x > 0.01 && tilt.y < -0.01 && tilt.x < 1 && tilt.y > -1
    for _ in 0..<50 { tilt.update(roll: 3, pitch: -3) }
    let capped = tilt.x <= 1 && tilt.y >= -1 && tilt.x > 0.99 && tilt.y < -0.99
    let beforeInvalid = tilt.x
    tilt.update(roll: .nan, pitch: .infinity)
    let tiltOK = smallTiltWorks && capped && tilt.x == beforeInvalid
    print("\(tiltOK ? "PASS" : "FAIL")  foil responds to small relative tilts, clamps and ignores invalid samples")
    allOK = allOK && tiltOK
    let starOK = CardStarCycle.opacity(index: 0, elapsed: 1.0) == 0
        && CardStarCycle.opacity(index: 3, elapsed: 1.0) == 1
        && CardStarCycle.opacity(index: 0, elapsed: 2.8) == 1
        && CardStarCycle.opacity(index: 3, elapsed: 2.8) == 0
        && (0..<4).allSatisfy { CardStarCycle.opacity(index: $0, elapsed: 4.2) == 1 }
        && CardStarCycle.opacity(index: 0, elapsed: CardStarCycle.duration + 1.0) == 0
    print("\(starOK ? "PASS" : "FAIL")  stars fade in order, return and repeat")
    allOK = allOK && starOK
    var appLock = AppLockState()
    let startsLocked = !appLock.isUnlocked
    let firstAttempt = appLock.generation
    appLock.unlock(ifGenerationMatches: firstAttempt)
    let unlockedAfterAuth = appLock.isUnlocked
    appLock.lock()
    appLock.unlock(ifGenerationMatches: firstAttempt)
    let rejectsBackgroundedAttempt = !appLock.isUnlocked
    appLock.unlock(ifGenerationMatches: appLock.generation)
    let lockOK = startsLocked && unlockedAfterAuth && rejectsBackgroundedAttempt && appLock.isUnlocked
    print("\(lockOK ? "PASS" : "FAIL")  app relock rejects stale authentication completions")
    allOK = allOK && lockOK
    let signatureSource = CGImageSourceCreateWithData(store.signaturePNG as CFData, nil)
    let imageOK = signatureSource.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        .map { $0.width == 600 && $0.height == 180 } ?? false
    let fallbackOK = DemoLicenceImages.portrait(named: "missing-demo.jpg") == DemoLicenceImages.portrait(named: nil)
        && DemoLicenceImages.signature(named: "missing-demo.png") == store.signaturePNG
    print("\(imageOK && fallbackOK ? "PASS" : "FAIL")  signature PNG dimensions and missing image fallbacks")
    allOK = allOK && imageOK && fallbackOK
    do {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        try store.signaturePNG.write(to: file)
        let loaded = DemoLicenceImages.image(named: file.path)
        let pathOK = loaded?.width == 600 && loaded?.height == 180
            && !DemoLicenceImages.portrait(named: file.path).isEmpty
        print("\(pathOK ? "PASS" : "FAIL")  absolute image file path loading")
        allOK = allOK && pathOK
    } catch {
        print("FAIL image path loading: \(error)")
        allOK = false
    }
    // Date-only age check around midnight and the eighteenth birthday.
    for zone in ["Australia/Sydney", "America/Los_Angeles"] {
        let timeZone = TimeZone(identifier: zone)!
        let formatter = ISO8601DateFormatter()
        let midnight = zone == "Australia/Sydney" ? "2026-11-15T13:00:00Z" : "2026-11-16T08:00:00Z"
        let birthday = formatter.date(from: midnight)!
        let ageOK = DemoLicenceData.age("2008-11-16", now: birthday - 1, timeZone: timeZone) == 17
            && DemoLicenceData.age("2008-11-16", now: birthday, timeZone: timeZone) == 18
            && DemoLicenceData.age("2008-11-16", now: birthday + 86_400, timeZone: timeZone) == 18
            && DemoLicenceData.age("invalid", now: birthday, timeZone: timeZone) == 0
            && DemoLicenceData.age("2030-11-16", now: birthday, timeZone: timeZone) == 0
        print("\(ageOK ? "PASS" : "FAIL")  eighteenth birthday at local midnight: \(zone)")
        allOK = allOK && ageOK
    }
    // A custom render fixture must survive serialization and reach the UI credential.
    var fixture = SharedAppData.demo
    fixture.licence.firstNames = "Taylor"
    fixture.licence.surname = "EXAMPLE"
    fixture.licence.licenceNumber = "TEST0042"
    fixture.licence.cardVersion = "002"
    fixture.licence.dateOfBirth = "1990-02-15"
    fixture.licence.issueDate = "2026-01-01"
    fixture.licence.expiryDate = "2036-01-01"
    fixture.licence.classes = [.init(iso: "B", nzClass: "1", stage: "F")]
    fixture.licence.endorsements = ["P"]
    do {
        let decoded = try JSONDecoder().decode(SharedAppData.self, from: JSONEncoder().encode(fixture))
        let customStore = WalletStore(appData: decoded)
        let c = customStore.credentials[0]
        let expected = ["firstNames": "Taylor", "surname": "EXAMPLE", "fullName": "Taylor EXAMPLE",
                        "licenceNumber": "TEST0042", "cardVersion": "002", "dateOfBirth": "1990-02-15",
                        "licenceClass": "1F", "endorsements": "P"]
        let passed = decoded == fixture && expected.allSatisfy { c.value($0.key) == $0.value }
            && c.issuedAt == DemoLicenceData.date(fixture.licence.issueDate)
            && c.expiresAt == DemoLicenceData.date(fixture.licence.expiryDate)
            && SharedAppData.demo.licence == DemoLicenceData.current
        print("\(passed ? "PASS" : "FAIL")  shared app data round-trip and custom licence issuance")
        allOK = allOK && passed
    } catch {
        print("FAIL shared app data serialization: \(error)")
        allOK = false
    }
    let expectations: [(AttackSimulation, Bool, String)] = [
        (.none, true, "result.valid"),
        (.tamperedClaim, false, "result.invalid"),
        (.forgedIssuer, false, "result.invalid"),
        (.replay, false, "result.invalid"),
        (.revoked, false, "result.invalid"),
        (.expired, false, "result.expired"),
    ]
    for scenario in Scenario.allCases {
        guard let cred = store.credentials.first(where: { scenario.acceptedTypes.contains($0.type) }) else {
            print("FAIL no credential for \(scenario)"); allOK = false; continue
        }
        for (attack, shouldPass, expectedTitle) in expectations {
            let req = VerificationRequest(scenario: scenario)
            let r = store.runVerification(request: req, credential: cred, attack: attack, offline: false)
            let title: String = switch r.outcome {
            case .valid: "result.valid"
            case .validOffline: "result.validOffline"
            case .invalid: "result.invalid"
            case .expired: "result.expired"
            case .unverifiable: "result.unverifiable"
            }
            let ok = r.outcome.isPositive == shouldPass && title == expectedTitle
            let failed = r.checks.first { !$0.passed }?.labelKey ?? "-"
            print("\(ok ? "PASS" : "FAIL")  \(scenario.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(attack.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)) → \(title)  (failed check: \(failed))")
            if ok && shouldPass {
                // Selective disclosure: verifier must receive exactly the requested claims.
                let got = Set(r.disclosed.map(\.key)), want = Set(scenario.requestedClaims)
                if got != want { print("FAIL  disclosed \(got) != requested \(want)"); allOK = false }
            }
            allOK = allOK && ok
        }
    }
    // Offline mode must never report a plain "valid".
    let req = VerificationRequest(scenario: .age)
    let r = store.runVerification(request: req, credential: store.credentials[0], attack: .none, offline: true)
    if case .validOffline = r.outcome { print("PASS  offline   none           → result.validOffline") }
    else { print("FAIL  offline did not return validOffline"); allOK = false }
    return allOK
}

let ok = MainActor.assumeIsolated { run() && runMDLTests() }
print(ok ? "\nALL TESTS PASSED" : "\nSOME TESTS FAILED")
exit(ok ? 0 : 1)
