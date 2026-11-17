// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @State private var showRightsAlert = false

    private let rights: [(String, String)] = [
        ("rights.access", "doc.text.magnifyingglass"),
        ("rights.correct", "pencil.and.list.clipboard"),
        ("rights.withdraw", "hand.raised.slash"),
        ("rights.report", "exclamationmark.bubble"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GovNotice(text: settings.t("activity.privacyNote"), icon: "lock.iphone", color: .nzAccent)

                    GovPanel(title: settings.t("activity.history")) {
                        if store.activity.isEmpty {
                            Text(settings.t("activity.empty")).font(.gov(.body)).foregroundStyle(Color.govMuted).padding(16)
                        }
                        ForEach(Array(store.activity.enumerated()), id: \.element.id) { i, e in
                            VStack(alignment: .leading, spacing: 0) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(settings.t(e.scenario.verifierNameKey)).font(.gov(.body, .semibold)).foregroundStyle(Color.govInk)
                                        Spacer()
                                        Text(settings.date(e.date, time: true)).font(.gov(.caption)).foregroundStyle(Color.govMuted)
                                    }
                                    if !e.sharedClaims.isEmpty {
                                        Text(settings.claimList(e.sharedClaims)).font(.gov(.subheadline)).foregroundStyle(Color.govMuted)
                                    }
                                    Label(settings.t(e.outcomeKey), systemImage: e.positive ? "arrow.up.forward.circle.fill" : "xmark.circle.fill")
                                        .font(.gov(.caption, .semibold))
                                        .foregroundStyle(e.positive ? Color.nzAccent : Color.govMuted)
                                }
                                .padding(16)
                                if i < store.activity.count - 1 { Rectangle().fill(Color.govLine).frame(height: 1).padding(.leading, 16) }
                            }
                        }
                    }

                    GovPanel(title: settings.t("rights.title")) {
                        ForEach(Array(rights.enumerated()), id: \.offset) { i, r in
                            Button { showRightsAlert = true } label: {
                                GovLinkRow(icon: r.1, title: settings.t(r.0), showDivider: i < rights.count - 1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
            .background(Color.govPage)
            .govHeader(settings.t("tab.activity"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("common.done")) { dismiss() }.foregroundStyle(Color.nzInk)
                }
            }
            .alert(settings.t("rights.prototypeTitle"), isPresented: $showRightsAlert) {
                Button(settings.t("common.ok")) {}
            } message: { Text(settings.t("rights.prototypeMsg")) }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Profile
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 14) {
                            LicencePortrait().frame(width: 56, height: 74).clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: store.credentials.first?.value("fullName") ?? "").font(.gov(.title3, .bold)).foregroundStyle(Color.nzInk)
                                Label(settings.t("account.verified"), systemImage: "person.crop.circle")
                                    .font(.gov(.caption, .semibold)).foregroundStyle(Color.nzAccent)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))
                        GovFootnote(text: settings.t("account.verifiedFooter"))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        GovPanel(title: settings.t("settings.language")) {
                            LanguagePicker().padding(16)
                        }
                        GovFootnote(text: settings.t("settings.languageFooter"))
                    }

                    GovPanel(title: settings.t("settings.privacy")) {
                        Button { showHistory = true } label: {
                            GovLinkRow(icon: "clock.arrow.circlepath", title: settings.t("settings.history"), showDivider: false)
                        }
                        .buttonStyle(.plain)
                    }

                    GovPanel(title: settings.t("settings.security")) {
                        GovRow(label: settings.t("settings.deviceKey"),
                               value: settings.t(store.holderKey.isHardwareBacked ? "key.secureEnclave" : "key.software"))
                        GovRow(label: settings.t("settings.trustedIssuers"), value: "\(store.verifier.trustRegistry.count)")
                        GovRow(label: settings.t("settings.signatureAlg"), value: "ECDSA P-256 / SHA-256", showDivider: false)
                    }

                    GovPanel(title: settings.t("settings.about")) {
                        Text(settings.t("settings.disclaimer")).font(.gov(.footnote)).foregroundStyle(Color.govMuted)
                            .padding(16)
                        Rectangle().fill(Color.govLine).frame(height: 1).padding(.leading, 16)
                        GovRow(label: settings.t("settings.version"), value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")

                    }

                }
                .padding(16)
            }
            .background(Color.govPage)
            .govHeader(settings.t("tab.account"))
            .sheet(isPresented: $showHistory) { ActivityView() }
        }
    }
}
