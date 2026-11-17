// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

// Front-end only mock screens for the government services. None of these call a
// backend or move real money; each ends in a "TEST" confirmation so it is obvious
// in a demo that nothing was actually submitted. In production these flows would
// talk to the relevant agency (NZTA, etc.) over its own secure API.

/// A dark submit button plus a TEST confirmation alert, reused by every mock form.
private struct MockSubmit: View {
    @EnvironmentObject private var settings: AppSettings
    let label: String
    let doneTitle: String
    let doneMessage: String
    var disabled = false
    @State private var done = false

    var body: some View {
        Button { done = true } label: { Text(settings.t(label)) }
            .buttonStyle(GovButtonStyle())
            .disabled(disabled)
            .alert(settings.t(doneTitle), isPresented: $done) {
                Button(settings.t("common.ok")) {}
            } message: { Text(settings.t(doneMessage)) }
    }
}

/// Small helper: a labelled text field in the flat style.
private struct GovField: View {
    @EnvironmentObject private var settings: AppSettings
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(settings.t(label)).font(.gov(.footnote)).foregroundStyle(Color.govMuted)
            TextField("", text: $text)
                .font(.gov(.body))
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))
        }
    }
}

// MARK: - Renew driver licence (form)

struct RenewLicenceView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @State private var useExistingPhoto = true

    var body: some View {
        let c = store.credentials.first
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GovNotice(text: settings.t("renew.eligible"), icon: "checkmark.circle.fill", color: .nzAccent)

                GovPanel(title: settings.t("renew.current")) {
                    GovRow(label: settings.t("claim.licenceNumber"), value: c?.value("licenceNumber") ?? "—")
                    GovRow(label: settings.t("licence.expiry"), value: c?.expiresAt.map(CardDate.format) ?? "—")
                    // New expiry = 10 years from today (NZ full licences renew for 10 years).
                    GovRow(label: settings.t("renew.newExpiry"),
                           value: CardDate.format(Calendar.current.date(byAdding: .year, value: 10, to: Date()) ?? Date()),
                           showDivider: false)
                }

                GovPanel(title: settings.t("renew.photoSection")) {
                    Toggle(isOn: $useExistingPhoto) {
                        Text(settings.t("renew.useExisting")).font(.gov(.body)).foregroundStyle(Color.govInk)
                    }
                    .tint(Color.nzAccent)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }

                GovPanel(title: settings.t("renew.feeSection")) {
                    GovRow(label: settings.t("renew.feeLabel"), value: "$49.60", showDivider: false)
                }

                MockSubmit(label: "renew.continue", doneTitle: "renew.done", doneMessage: "renew.doneMsg")
                GovFootnote(text: settings.t("renew.testNote"))

            }
            .padding(16)
        }
        .background(Color.govPage)
        .govHeader(settings.t("service.renewLicence"))
    }
}

// MARK: - Demerit points (the holder's own data)

struct DemeritPointsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @State private var web: IdentifiedURL?

    var body: some View {
        let points = Int(store.credentials.first?.value("demeritPoints") ?? "0") ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GovPanel(title: nil) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(settings.t("demerit.of100", points)).font(.gov(.title, .bold)).foregroundStyle(Color.nzInk)
                        ProgressView(value: Double(points), total: 100).tint(points >= 100 ? .red : Color.nzAccent)
                        Text(settings.t(points == 0 ? "demerit.none" : "demerit.explain"))
                            .font(.gov(.subheadline)).foregroundStyle(Color.govMuted)
                    }
                    .padding(16)
                }

                // Content-only explanation lives on the official site, so link out to it.
                Button { web = IdentifiedURL(url: URL(string: "https://www.nzta.govt.nz/driver-licences/getting-a-licence/demerit-points-and-your-licence/")!) } label: {
                    GovLinkRow(icon: "info.circle.fill", title: settings.t("demerit.learnMore"),
                               tag: settings.t("services.website"), chevron: false, tint: .nzAccent, showDivider: false)
                }
                .buttonStyle(.plain)
                .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))

            }
            .padding(16)
        }
        .background(Color.govPage)
        .govHeader(settings.t("service.points"))
        .sheet(item: $web) { SafariView(url: $0.url).ignoresSafeArea() }
    }
}

// MARK: - Book a driving test (form)

struct BookTestView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var practical = true
    @State private var location = ""
    @State private var date = Date()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GovPanel(title: settings.t("bookTest.typeSection")) {
                    Picker("", selection: $practical) {
                        Text(settings.t("bookTest.theory")).tag(false)
                        Text(settings.t("bookTest.practical")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(16)
                }

                GovPanel(title: settings.t("bookTest.locationSection")) {
                    GovField(label: "bookTest.location", text: $location).padding(16)
                }

                GovPanel(title: settings.t("bookTest.dateSection")) {
                    DatePicker("", selection: $date, in: Date()..., displayedComponents: .date)
                        .labelsHidden()
                        .padding(16)
                }

                MockSubmit(label: "bookTest.find", doneTitle: "bookTest.done", doneMessage: "bookTest.doneMsg")
                GovFootnote(text: settings.t("bookTest.testNote"))

            }
            .padding(16)
        }
        .background(Color.govPage)
        .govHeader(settings.t("service.test"))
    }
}

// MARK: - My vehicles (the holder's own data)

struct VehiclesView: View {
    @EnvironmentObject private var settings: AppSettings

    // Demo vehicle only.
    private let plate = "ABC123"
    private let make = "2019 Toyota Corolla"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GovPanel(title: nil) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: plate).font(.gov(.title3, .heavy)).foregroundStyle(Color.nzInk)
                                Text(verbatim: make).font(.gov(.subheadline)).foregroundStyle(Color.govMuted)
                            }
                            Spacer()
                            StatusPillText(text: settings.t("vehicles.current"), color: Color(red: 0.13, green: 0.55, blue: 0.27))
                        }
                        .padding(16)
                        Rectangle().fill(Color.govLine).frame(height: 1)
                        GovRow(label: settings.t("vehicles.regoExpiry"),
                               value: CardDate.format(Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()))
                        GovRow(label: settings.t("vehicles.wofExpiry"),
                               value: CardDate.format(Calendar.current.date(byAdding: .month, value: 7, to: Date()) ?? Date()),
                               showDivider: false)
                    }
                }
                MockSubmit(label: "vehicles.renew", doneTitle: "vehicles.done", doneMessage: "vehicles.doneMsg")
                GovFootnote(text: settings.t("vehicles.testNote"))

            }
            .padding(16)
        }
        .background(Color.govPage)
        .govHeader(settings.t("service.vehicles"))
    }
}

/// Small coloured status chip used on the vehicle panel.
private struct StatusPillText: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.gov(.caption, .bold)).textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}

// MARK: - Pay an infringement fee (front-end only — no real payment)

struct InfringementView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GovPanel(title: settings.t("infringement.heading")) {
                    GovRow(label: settings.t("infringement.reason"), value: settings.t("infringement.reasonValue"))
                    GovRow(label: settings.t("infringement.issued"),
                           value: CardDate.format(Calendar.current.date(byAdding: .day, value: -9, to: Date()) ?? Date()))
                    GovRow(label: settings.t("infringement.amount"), value: "$150.00")
                    GovRow(label: settings.t("infringement.due"),
                           value: CardDate.format(Calendar.current.date(byAdding: .day, value: 19, to: Date()) ?? Date()),
                           showDivider: false)
                }
                // Front-end only: this does not collect card details or take a payment.
                // A real build would hand off to the government payment provider.
                MockSubmit(label: "infringement.pay", doneTitle: "infringement.done", doneMessage: "infringement.doneMsg")
                GovFootnote(text: settings.t("infringement.testNote"))

            }
            .padding(16)
        }
        .background(Color.govPage)
        .govHeader(settings.t("service.fines"))
    }
}

// MARK: - Update address (form)

struct UpdateAddressView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var street = ""
    @State private var suburb = ""
    @State private var city = ""
    @State private var postcode = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GovPanel(title: settings.t("address.heading")) {
                    VStack(spacing: 12) {
                        GovField(label: "address.street", text: $street)
                        GovField(label: "address.suburb", text: $suburb)
                        GovField(label: "address.cityField", text: $city)
                        GovField(label: "address.postcode", text: $postcode)
                    }
                    .padding(16)
                }
                GovNotice(text: settings.t("address.applies"), icon: "info.circle.fill", color: .nzAccent)
                MockSubmit(label: "address.submit", doneTitle: "address.done", doneMessage: "address.doneMsg",
                           disabled: street.isEmpty || city.isEmpty)
                GovFootnote(text: settings.t("address.testNote"))

            }
            .padding(16)
        }
        .background(Color.govPage)
        .govHeader(settings.t("service.address"))
    }
}
