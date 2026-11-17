// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct WalletView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @State private var showQR = false
    @State private var showLicence = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(settings.t("wallet.greeting", store.holderName))
                        .font(.gov(.headline))
                        .foregroundStyle(Color.govInk)

                    if let licence = store.credentials.first {
                        // "My licence / Tap to view licence" tile around the card.
                        VStack(alignment: .leading, spacing: 0) {
                            Button { showLicence = true } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(settings.t("wallet.myLicence"))
                                            .font(.gov(.title3, .bold)).foregroundStyle(Color.nzInk)
                                        Text(settings.t("wallet.tapToView"))
                                            .font(.gov(.footnote)).foregroundStyle(Color.govMuted)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.gov(.body, .semibold)).foregroundStyle(Color.nzInk)
                                }
                                .padding(14)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(settings.t("wallet.tapToOpen"))
                            LicenceCompactCard(credential: licence, openLicence: { showLicence = true })
                                .padding([.horizontal, .bottom], 12)
                        }
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))

                        Button { showQR = true } label: {
                            Label(settings.t("detail.showQR"), systemImage: "qrcode")
                        }
                        .buttonStyle(GovButtonStyle())

                        Text(settings.t("wallet.lastRefreshed", settings.date(store.lastRefreshed, time: true)))
                            .font(.gov(.footnote))
                            .foregroundStyle(Color.govMuted)
                            .frame(maxWidth: .infinity)
                    }

                    GovNotice(text: settings.t("wallet.securityNote"), icon: "lock.shield.fill")

                }
                .padding(16)
            }
            .background(Color.govPage)
            .refreshable { await store.refresh() }
            .govHeader(settings.t("wallet.title"))
            .navigationDestination(isPresented: $showLicence) { LicenceView() }
            .sheet(isPresented: $showQR) {
                ShareLicenceView()
            }
        }
    }
}
