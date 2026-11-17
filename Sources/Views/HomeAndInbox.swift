// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Home: greeting, wallet preview, favourite services and a featured notice
/// (same order as the Service NSW home screen).
struct HomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @Binding var tab: String
    @State private var showQR = false

    @State private var web: IdentifiedURL?
    // A few of the catalogue's services, surfaced on Home like Service NSW's favourites.
    private var favourites: [GovService] {
        let wanted = ["service.renewLicence", "service.points", "service.fines", "service.vehicles"]
        let all = ServiceCatalog.groups.flatMap(\.items)
        return wanted.compactMap { id in all.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.t("home.greeting", store.credentials.first?.value("firstNames")?.components(separatedBy: " ").first ?? ""))
                            .font(.gov(.title2, .bold)).foregroundStyle(Color.nzInk)
                        Text(settings.t("home.subtitle")).font(.gov(.subheadline)).foregroundStyle(Color.govMuted)
                    }

                    // Wallet preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(settings.t("home.yourWallet")).font(.gov(.title3, .bold)).foregroundStyle(Color.nzInk)
                            Spacer()
                            Button(settings.t("home.seeAll")) { tab = "wallet" }
                                .font(.gov(.subheadline, .semibold)).foregroundStyle(Color.nzAccent)
                        }
                        if let licence = store.credentials.first {
                            LicenceCompactCard(credential: licence, openLicence: { tab = "wallet" })
                            Button { showQR = true } label: { Label(settings.t("detail.showQR"), systemImage: "qrcode") }
                                .buttonStyle(GovButtonStyle())
                        }
                    }

                    // Favourites
                    VStack(alignment: .leading, spacing: 8) {
                        Text(settings.t("home.favourites")).font(.gov(.title3, .bold)).foregroundStyle(Color.nzInk)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(favourites) { f in
                                favouriteTile(f)
                            }
                        }
                    }

                    GovNotice(text: settings.t("home.featured"), icon: "checkmark.shield.fill", color: .nzAccent)

                }
                .padding(16)
            }
            .background(Color.govPage)
            .refreshable { await store.refresh() }
            .govHeader(settings.t("tab.home"))
            .sheet(isPresented: $showQR) { ShareLicenceView() }
            .serviceRoutes(web: $web)
        }
    }

    @ViewBuilder
    private func favouriteTile(_ f: GovService) -> some View {
        let label = VStack(alignment: .leading, spacing: 10) {
            Image(systemName: f.icon).font(.system(size: 20)).foregroundStyle(Color.nzAccent)
            Text(settings.t(f.id)).font(.gov(.subheadline, .semibold)).foregroundStyle(Color.govInk)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))

        if f.isWeb {
            Button { if let u = f.webURL { web = IdentifiedURL(url: u) } } label: { label }.buttonStyle(.plain)
        } else {
            NavigationLink(value: f) { label }.buttonStyle(.plain)
        }
    }
}

/// Inbox: messages from agencies (demo content).
struct InboxView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore

    private let messages: [(title: String, body: String, icon: String, daysAgo: Double, unread: Bool)] = [
        ("inbox.added.title", "inbox.added.body", "wallet.pass.fill", 0, true),
        ("inbox.share.title", "inbox.share.body", "qrcode", 2, false),
        ("inbox.renew.title", "inbox.renew.body", "calendar", 30, false),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    GovPanel(title: nil) {
                        ForEach(Array(messages.enumerated()), id: \.offset) { i, m in
                            VStack(spacing: 0) {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: m.icon).font(.system(size: 18)).foregroundStyle(Color.nzAccent).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(settings.t(m.title)).font(.gov(.body, m.unread ? .bold : .semibold)).foregroundStyle(Color.govInk)
                                            Spacer()
                                            if m.unread { Circle().fill(Color.nzAccent).frame(width: 8, height: 8) }
                                        }
                                        Text(settings.t(m.body)).font(.gov(.subheadline)).foregroundStyle(Color.govMuted)
                                        Text(settings.date(Date() - m.daysAgo * 86_400)).font(.gov(.caption)).foregroundStyle(Color.govMuted)
                                    }
                                }
                                .padding(14)
                                if i < messages.count - 1 { Rectangle().fill(Color.govLine).frame(height: 1).padding(.leading, 52) }
                            }
                        }
                    }

                }
                .padding(16)
            }
            .background(Color.govPage)
            .govHeader(settings.t("tab.inbox"))
        }
    }
}
