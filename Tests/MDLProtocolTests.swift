// SPDX-License-Identifier: GPL-3.0-only
// ISO 18013-5 holder ↔ reader tests over the in-memory transport.
import Foundation
import CryptoKit

@MainActor func runMDLTests() -> Bool {
    print("\n— ISO 18013-5 mDL —")
    let store = WalletStore()
    var allOK = true
    func check(_ ok: Bool, _ label: String) { print("\(ok ? "PASS" : "FAIL")  \(label)"); allOK = allOK && ok }

    /// Runs one full session. `tamper` edits the holder's outgoing response bytes.
    func session(_ scenario: Scenario, document: IssuedMDoc? = nil, deviceSigner: ((Data) throws -> Data)? = nil,
                 trust: [Data] = WalletStore.mdlTrustList, approveAll: Bool = true,
                 intercept: ((Data) -> Data)? = nil) -> (MDLReaderSession.State?, MDLHolderSession.State) {
        let holder = MDLHolderSession(document: document ?? store.mdoc!,
                                      deviceSigner: deviceSigner ?? COSE.rawSigner(store.holderKey))
        guard let reader = MDLReaderSession(qr: holder.engagement.qrString, request: scenario.mdlRequest,
                                            trustedIACAKeys: trust) else { return (nil, holder.state) }
        let (h, r) = LoopbackTransport.pair(async: false)
        h.tap = intercept
        holder.attach(h)
        var final: MDLReaderSession.State?
        reader.onStateChange = { final = $0 }
        holder.onStateChange = { st in
            if case .requested(let req) = st {
                if approveAll { holder.approve(req.elements.mapValues { Set($0.keys) }) } else { holder.decline() }
            }
        }
        reader.start(r)
        return (final, holder.state)
    }

    // 1. QR code format
    let hs = store.makeHolderSession()!
    let qr = hs.engagement.qrString
    check(qr.hasPrefix("mdoc:") && DeviceEngagement(qr: qr)?.peripheralServerUUID != nil,
          "engagement QR is mdoc: + base64url, offers BLE peripheral server mode (\(qr.count) chars)")

    // 2. Happy path for each scenario, and only requested elements disclosed
    for sc in Scenario.allCases {
        let (st, _) = session(sc)
        if case .done(let v)? = st {
            if let portrait = v.value("portrait")?.bytes {
                check(portrait == store.portraitJPEG, "mDL portrait matches the displayed portrait bytes")
            }
            let got = Set(v.elements[MDL.namespace]?.keys.map { $0 } ?? [])
            let want = Set(sc.mdlRequest.elements[MDL.namespace]!.keys)
            check(v.outcome == .valid && got == want && v.checks.allSatisfy(\.passed),
                  "\(sc.rawValue): valid, disclosed exactly \(want.count) requested elements")
        } else { check(false, "\(sc.rawValue): no result \(String(describing: st))") }
    }

    // 3. Holder declines
    let (dst, hst) = session(.identity, approveAll: false)
    if case .failed(let r)? = dst { check(r == "mdl.reason.declined" && hst == .declined, "holder declines → reader told, nothing shared") }
    else { check(false, "decline: \(String(describing: dst))") }

    // 4. Forged issuer: same data signed by an IACA the reader does not trust
    let rogue = P256.Signing.PrivateKey()
    let forgedDoc = store.mdlIssuer.issue(elements: [MDL.namespace: [("age_over_18", .bool(true)), ("portrait", .bytes(DemoPortrait.jpeg))]],
                                          deviceKeyX963: store.holderKey.publicKeyRaw, signed: Date(), validFrom: Date() - 60,
                                          validUntil: Date() + 86_400, signer: COSE.rawSigner(rogue))
    if case .done(let v)? = session(.age, document: forgedDoc).0 {
        check(v.outcome == .invalid("mdl.reason.issuerSignature"), "forged issuer signature → invalid")
    } else { check(false, "forged issuer: no result") }

    // 5. Untrusted (foreign) issuer: valid signatures, root not in trust list
    if case .done(let v)? = session(.age, trust: []).0 {
        check(v.outcome == .untrustedIssuer && v.checks.first { $0.id == "mdl.check.issuerTrusted" }?.passed == false,
              "valid licence from an issuer not in the trust list → untrusted (data still shown)")
    } else { check(false, "untrusted: no result") }

    // 6. Copied licence on another phone (no access to the device key)
    let thief = P256.Signing.PrivateKey()
    if case .done(let v)? = session(.identity, deviceSigner: COSE.rawSigner(thief)).0 {
        check(v.outcome == .invalid("mdl.reason.deviceSignature"), "cloned licence without the phone's key → invalid")
    } else { check(false, "clone: no result") }

    // 7. Expired
    let expired = store.issueMDoc(validUntil: Date() - 86_400)
    if case .done(let v)? = session(.driver, document: expired).0 {
        check(v.outcome == .expired, "expired licence → expired")
    } else { check(false, "expired: no result") }

    // 8. Tampered element: change a value inside an issuer-signed item (re-encrypted by an attacker
    //    who controls the holder app; signatures cannot be fixed).
    var tamperedItems = store.mdoc!.items
    if var list = tamperedItems[MDL.namespace],
       let idx = list.firstIndex(where: { (try? CBOR.decode($0))?.embeddedRaw.flatMap { try? CBOR.decode($0) }?["elementIdentifier"]?.text == "age_over_18" }),
       let raw = (try? CBOR.decode(list[idx]))?.embeddedRaw, var pairs = (try? CBOR.decode(raw))?.pairs {
        if let j = pairs.firstIndex(where: { $0.key == .text("elementValue") }) { pairs[j].value = .bool(false) }
        list[idx] = CBOR.embedded(.map(pairs)).encoded()
        tamperedItems[MDL.namespace] = list
    }
    let tamperedDoc = IssuedMDoc(items: tamperedItems, issuerAuth: store.mdoc!.issuerAuth, validUntil: store.mdoc!.validUntil)
    if case .done(let v)? = session(.age, document: tamperedDoc).0 {
        check(v.outcome == .invalid("mdl.reason.tampered"), "edited data element → invalid")
    } else { check(false, "tamper: no result") }

    // 9. Replay: response captured from one session played into another
    var captured: Data?
    _ = session(.age, intercept: { d in if (try? CBOR.decode(d))?["data"] != nil { captured = d }; return d })
    if let old = captured {
        let (st, _) = session(.age, intercept: { _ in old })
        if case .failed(let r)? = st { check(r == "mdl.reason.decrypt", "replayed response from an earlier session → rejected") }
        else { check(false, "replay: \(String(describing: st))") }
    } else { check(false, "replay: nothing captured") }

    // 9b. NSW/ISO profile rules on what we issue
    if let ds = try? X509.Parsed(store.mdlIssuer.dsCert), let a = ds.notBefore, let b = ds.notAfter,
       let msoRaw = (try? CBOR.decode(store.mdoc!.issuerAuth.payload!))?.embeddedRaw, let mso = try? CBOR.decode(msoRaw),
       let signed = mso["validityInfo"]?["signed"]?.date, let from = mso["validityInfo"]?["validFrom"]?.date {
        check(b.timeIntervalSince(a) <= 457 * 86_400, "document signer certificate valid ≤ 457 days (NSW rule)")
        check(signed <= from && signed >= a, "MSO signed ≤ validFrom and within signer validity (NSW rule)")
    } else { check(false, "profile: could not parse") }
    let badDates = store.mdlIssuer.issue(elements: [MDL.namespace: [("age_over_18", .bool(true)), ("portrait", .bytes(DemoPortrait.jpeg))]],
                                         deviceKeyX963: store.holderKey.publicKeyRaw, signed: Date(), validFrom: Date() - 3_600,
                                         validUntil: Date() + 86_400)
    if case .done(let v)? = session(.age, document: badDates).0 {
        check(v.outcome == .invalid("mdl.reason.dates"), "licence signed after its valid-from date → rejected, as NSW does")
    } else { check(false, "bad dates: no result") }

    // 10. CBOR round trip incl. indefinite-length and floats
    let sample = CBOR.map([(.text("a"), .array([.int(-500), .bytes(Data([1, 2])), .double(1.5), .null, .bool(true)]))])
    check((try? CBOR.decode(sample.encoded())) == sample, "CBOR encode/decode round trip")
    check((try? CBOR.decode(Data([0x9F, 0x01, 0x02, 0xFF]))) == .array([.int(1), .int(2)]), "CBOR indefinite-length array")

    // 11. Certificates parse and chain
    if let ds = try? X509.Parsed(store.mdlIssuer.dsCert), let iaca = try? X509.Parsed(store.mdlIssuer.iacaCert) {
        check(ds.isSigned(byX963: MDLIssuer.iacaPublicKey) && iaca.isSigned(byX963: MDLIssuer.iacaPublicKey)
              && ds.isValid(at: Date()) && ds.country == "NZ", "IACA → document signer certificate chain verifies")
    } else { check(false, "certificates did not parse") }

    if let dir = ProcessInfo.processInfo.environment["CW_DUMP_DIR"] {
        try? store.mdlIssuer.iacaCert.write(to: URL(fileURLWithPath: dir + "/iaca.der"))
        try? store.mdlIssuer.dsCert.write(to: URL(fileURLWithPath: dir + "/ds.der"))
    }
    print("QR payload: \(qr.count) characters (was ~1,200 for the old signed QR)")
    return allOK
}
