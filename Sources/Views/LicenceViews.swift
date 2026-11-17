// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Field as printed on the card: English label with te reo Māori, then the value.
/// Numbers follow the usual driving-licence field numbering (1 surname, 2 first names, …).
struct CardField: View {
    var number: String? = nil
    let en: String
    let mi: String
    let value: String
    var big = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: [number.map { "\($0)." }, "\(en) · \(mi)"].compactMap { $0 }.joined(separator: " "))
                .font(.gov(size: 9, weight: .semibold))
                .foregroundStyle(Color.govMuted)
            Text(verbatim: value)
                .font(.gov(size: big ? 16 : 13, weight: big ? .bold : .semibold))
                .foregroundStyle(Color.govInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Card stock: pale pounamu tint, fine waves, rosette print and holographic foil.
private struct CardBackground: View {
    var center = UnitPoint(x: 0.8, y: 0.6)
    var radius: CGFloat = 0.45

    var body: some View {
        ZStack {
            Color.govPaper
            SecurityWaves().stroke(Color.nzAccent.opacity(0.07), lineWidth: 0.6)
            // Broad, low-opacity foil lets the colour shift read across the card.
            HologramFoil(shape: Rectangle(), filled: true, strength: 0.16)
            GeometryReader { geo in
                let size = min(geo.size.height * 0.95, geo.size.width * 0.78)
                KowhaiFlower().fill(Color(red: 0.80, green: 0.63, blue: 0.16).opacity(0.15))
                    .frame(width: size, height: size)
                    .position(x: geo.size.width * 0.77, y: geo.size.height * 0.52)
                HologramFoil(shape: KowhaiFlower(), lineWidth: 1.8, filled: true, strength: 0.42)
                    .frame(width: size, height: size)
                    .position(x: geo.size.width * 0.77, y: geo.size.height * 0.52)
                KowhaiFlower().stroke(Color.nzAccent.opacity(0.20), lineWidth: 1.0)
                    .frame(width: size, height: size)
                    .position(x: geo.size.width * 0.77, y: geo.size.height * 0.52)
            }
        }
        .clipped()
    }
}

extension Credential {
    func v(_ key: String) -> String { value(key) ?? "" }
    var surnameUpper: String { v("surname").uppercased() }
    var firstNamesUpper: String { v("firstNames").uppercased() }
    var isDonor: Bool { value("donor") == "true" }
}

private struct DonorBadge: View {
    var body: some View {
        Text(verbatim: "DONOR")
            .font(.gov(size: 9, weight: .heavy)).tracking(1)
            .foregroundStyle(Color.nzAccent)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.nzAccent, lineWidth: 1))
    }
}

/// Shared portrait bytes also feed the signed mDL, avoiding mismatched photos.
struct LicencePortrait: View {
    @EnvironmentObject private var store: WalletStore
    var body: some View {
        if let image = UIImage(data: store.portraitJPEG) {
            Image(uiImage: image).resizable().scaledToFill().clipped()
                .accessibilityLabel("Test licence portrait")
        } else {
            PlaceholderPortrait()
        }
    }
}

private struct LicenceSignature: View {
    @EnvironmentObject private var store: WalletStore
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "7. Signature · Waitohu")
                .font(.gov(size: 9, weight: .semibold))
                .foregroundStyle(Color.govMuted)
            if let image = UIImage(data: store.signaturePNG) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: 150, height: 45, alignment: .leading)
                    .accessibilityLabel("Fictional test signature")
            }
        }
    }
}

// MARK: - Compact card (wallet list)

struct LicenceCompactCard: View {
    let credential: Credential
    var openLicence: (() -> Void)? = nil

    var body: some View {
        let c = credential
        VStack(spacing: 0) {
            NZCardHeader(compact: true)
            Button { openLicence?() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        LicencePortrait()
                            .frame(width: 66, height: 88)
                            .overlay(Rectangle().stroke(Color.govInk.opacity(0.25)))
                        VStack(alignment: .leading, spacing: 5) {
                            CardField(en: "Name", mi: "Ingoa", value: "\(c.firstNamesUpper) \(c.surnameUpper)", big: true)
                            CardField(en: "Licence no.", mi: "Tau raihana", value: c.v("licenceNumber"))
                            CardField(en: "Expiry", mi: "Rā pau", value: c.expiresAt.map(CardDate.format) ?? "—")
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        AgePill(dateOfBirth: c.v("dateOfBirth"))
                        Spacer()
                        LiveClock().foregroundStyle(Color.govInk)
                    }
                }
                .padding(12)
                .background(CardBackground(center: UnitPoint(x: 0.86, y: 0.5), radius: 0.55))
            }
            .buttonStyle(.plain)
            .disabled(openLicence == nil)

        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.govLine))
    }
}

// MARK: - Full licence (all printed fields)

struct LicenceDocument: View {
    let credential: Credential

    var body: some View {
        let c = credential
        VStack(spacing: 0) {
            NZCardHeader()
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    LicencePortrait()
                        .frame(width: 96, height: 128)
                        .overlay(Rectangle().stroke(Color.govInk.opacity(0.25)))
                        .overlay(alignment: .bottomTrailing) {
                            // Holographic Southern Cross over the photo corner.
                            HologramFoil(shape: NZMarkShape(), lineWidth: 1.4, strength: 0.75)
                                .frame(width: 40, height: 40)
                                .offset(x: 14, y: 10)
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        CardField(number: "1", en: "Surname", mi: "Ingoa whānau", value: c.surnameUpper, big: true)
                        CardField(number: "2", en: "First names", mi: "Ingoa tuatahi", value: c.firstNamesUpper, big: true)
                        CardField(number: "3", en: "Date of birth", mi: "Rā whānau", value: CardDate.iso(c.v("dateOfBirth")))
                        if c.isDonor { DonorBadge() }
                    }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .top) {
                    CardField(number: "5", en: "Licence no.", mi: "Tau raihana", value: c.v("licenceNumber"), big: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CardField(number: "5a", en: "Card version", mi: "Putanga kāri", value: c.v("cardVersion"), big: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top) {
                    CardField(number: "4a", en: "Issue date", mi: "Rā tuku", value: CardDate.format(c.issuedAt))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CardField(number: "4b", en: "Expiry", mi: "Rā pau", value: c.expiresAt.map(CardDate.format) ?? "—")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(alignment: .top) {
                    CardField(number: "9", en: "Classes", mi: "Karaehe", value: c.v("licenceClass"), big: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CardField(number: "12", en: "Endorsements", mi: "Tohu tāpiri",
                              value: c.v("endorsements") == "none" ? "—" : c.v("endorsements"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                LicenceSignature()

                HStack(alignment: .bottom) {
                    AgePill(dateOfBirth: c.v("dateOfBirth"))
                    Spacer()
                    // Ghost image: small translucent second portrait, a standard card security feature.
                    LicencePortrait().frame(width: 24, height: 32).opacity(0.35)
                    LiveClock().foregroundStyle(Color.govInk)
                }
            }
            .padding(14)
            .background(CardBackground())

        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.govLine))
    }
}

// MARK: - Licence page

struct LicenceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @State private var showQR = false

    private var backLink: some View {
        Button { dismiss() } label: {
            HStack(spacing: 3) {
                Image(systemName: "chevron.left").font(.gov(.body, .semibold))
                Text(settings.t("wallet.title"))
            }
            .foregroundStyle(Color.nzInk)
        }
        .accessibilityLabel(settings.t("wallet.title"))
    }

    var body: some View {
        ScrollView {
            if let c = store.credentials.first {
                VStack(spacing: 14) {
                    LicenceDocument(credential: c)
                    TiltUnavailableNotice()

                    GovPanel(title: settings.t("licence.shareInPerson")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(settings.t("licence.shareNote")).font(.gov(.subheadline)).foregroundStyle(Color.govInk)
                            Button { showQR = true } label: {
                                Label(settings.t("detail.showQR"), systemImage: "qrcode")
                            }
                            .buttonStyle(GovButtonStyle())
                        }
                        .padding(16)
                    }

                    GovPanel(title: settings.t("licence.details")) {
                        let status: String = switch c.status() {
                        case .valid: settings.t("status.valid")
                        case .expiringSoon(let d): settings.t("status.expiresInDays", d)
                        case .expired: settings.t("status.expired")
                        }
                        GovRow(label: settings.t("claim.surname"), value: c.surnameUpper)
                        GovRow(label: settings.t("claim.firstNames"), value: c.firstNamesUpper)
                        GovRow(label: settings.t("claim.dateOfBirth"), value: CardDate.iso(c.v("dateOfBirth")))
                        GovRow(label: settings.t("claim.licenceNumber"), value: c.v("licenceNumber"))
                        GovRow(label: settings.t("claim.cardVersion"), value: c.v("cardVersion"))
                        GovRow(label: settings.t("claim.licenceClass"), value: c.v("licenceClass"))
                        GovRow(label: settings.t("licence.issued"), value: CardDate.format(c.issuedAt))
                        GovRow(label: settings.t("licence.expiry"), value: c.expiresAt.map(CardDate.format) ?? "—")
                        GovRow(label: settings.t("claim.endorsements"), value: settings.display("endorsements", c.v("endorsements")))
                        GovRow(label: settings.t("claim.conditions"), value: settings.display("conditions", c.v("conditions")))
                        GovRow(label: settings.t("claim.donor"), value: settings.display("donor", c.v("donor")))
                        GovRow(label: settings.t("licence.statusLabel"), value: status,
                               valueColor: { if case .expired = c.status() { return Color.red }; return Color(red: 0.18, green: 0.56, blue: 0.19) }(),
                               showDivider: false)
                    }

                    GovPanel(title: settings.t("licence.classes")) {
                        let classes = (c.value("licenceClass") ?? "")
                            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        ForEach(Array(classes.enumerated()), id: \.element) { i, cls in
                            HStack(alignment: .top, spacing: 12) {
                                Text(verbatim: cls)
                                    .font(.gov(.title3, .heavy))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 36)
                                    .background(Color.nzInk, in: RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(settings.t("class.\(cls.prefix(1))")).font(.gov(.subheadline, .semibold)).foregroundStyle(Color.govInk)
                                    Text(settings.t("stage.\(cls.dropFirst())")).font(.gov(.footnote)).foregroundStyle(Color.govMuted)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            if i < classes.count - 1 { Rectangle().fill(Color.govLine).frame(height: 1).padding(.leading, 14) }
                        }
                    }

                    GovPanel(title: settings.t("licence.digital")) {
                        let sigOK = store.issuerSignatureValid(c)
                        GovRow(label: settings.t("licence.points"),
                               value: settings.t("licence.pointsValue", c.value("demeritPoints") ?? "—"))
                        GovRow(label: settings.t("detail.issuer"), value: settings.t(c.type.issuerNameKey))
                        GovRow(label: settings.t("detail.signature"),
                               value: settings.t(sigOK ? "detail.sigValid" : "detail.sigInvalid"),
                               valueColor: sigOK ? Color(red: 0.18, green: 0.56, blue: 0.19) : .red)
                        GovRow(label: settings.t("detail.deviceKey"),
                               value: settings.t(store.holderKey.isHardwareBacked ? "key.secureEnclave" : "key.software"))
                        GovRow(label: settings.t("licence.lastRefreshed"),
                               value: settings.date(store.lastRefreshed, time: true), showDivider: false)
                    }

                }
                .padding(16)
            }
        }
        .background(Color.govPage)
        .refreshable { await store.refresh() }
        .govHeader(settings.t("licence.title"))
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Plain text back link instead of the round glass button.
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarLeading) { backLink }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .topBarLeading) { backLink }
            }
        }
        .sheet(isPresented: $showQR) {
            ShareLicenceView()
        }
    }
}
