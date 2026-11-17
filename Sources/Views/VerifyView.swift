// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct VerifyView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var scenario: Scenario = .age
    // `-attack forgedIssuer` / `-offline YES` launch args preselect for demos.
    @State private var attack = AttackSimulation(rawValue: UserDefaults.standard.string(forKey: "attack") ?? "") ?? .none
    @State private var offline = UserDefaults.standard.bool(forKey: "offline")
    @State private var activeRequest: VerificationRequest?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(settings.t("verify.intro")).font(.gov(.subheadline)).foregroundStyle(.secondary)
                }
                Section {
                    Picker(settings.t("verify.scenario"), selection: $scenario) {
                        ForEach(Scenario.allCases) { s in
                            Label(settings.t(s.titleKey), systemImage: s.icon).tag(s)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    LabeledContent(settings.t("verify.requests"), value: settings.claimList(scenario.requestedClaims))
                } header: { Text(settings.t("verify.scenario")) }

                Section {
                    Picker(settings.t("verify.attack"), selection: $attack) {
                        ForEach(AttackSimulation.allCases) { Text(settings.t($0.titleKey)).tag($0) }
                    }
                    .pickerStyle(.navigationLink)
                    Toggle(settings.t("verify.offline"), isOn: $offline)
                } header: {
                    Text(settings.t("verify.securityTests"))
                } footer: {
                    Text(settings.t("verify.attackFooter"))
                }

                Section {
                    Button { activeRequest = VerificationRequest(scenario: scenario, attack: attack, offline: offline) } label: {
                        Label(settings.t("verify.start"), systemImage: "qrcode.viewfinder")
                            .font(.gov(.headline))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .govHeader(settings.t("tab.verify"))
            .sheet(item: $activeRequest) { req in
                VerificationFlowView(request: req)
            }
        }
    }
}

struct VerificationFlowView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss

    let request: VerificationRequest

    enum Phase { case waiting, consent, result(VerificationResult) }
    @State private var phase: Phase = .waiting

    private var credential: Credential? {
        store.credentials.first { request.scenario.acceptedTypes.contains($0.type) }
    }
    private var verifierName: String { settings.t(request.scenario.verifierNameKey) }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .waiting: waiting
                case .consent: consent
                case .result(let r): ResultView(result: r)
                }
            }
            .govHeader(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(settings.t("common.close")) { dismiss() }
                }
            }
        }
    }

    private var title: String {
        switch phase {
        case .waiting: settings.t("verify.requestTitle")
        case .consent: settings.t("consent.title")
        case .result: settings.t("result.title")
        }
    }

    // MARK: Verifier shows a request QR

    private var waiting: some View {
        ScrollView {
            VStack(spacing: 18) {
                VerifierHeader(scenario: request.scenario)
                if let img = QRCode.image(request.qrPayload) {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        .shadow(radius: 4)
                }
                HStack(spacing: 8) {
                    ProgressView()
                    Text(settings.t("verify.waiting")).foregroundStyle(.secondary)
                }
                Divider()
                Text(settings.t("verify.demoHint")).font(.gov(.footnote)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    withAnimation { phase = .consent }
                } label: {
                    Label(settings.t("verify.respondHere"), systemImage: "wallet.pass.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
    }

    // MARK: Citizen sees a consent screen

    @ViewBuilder private var consent: some View {
        if let c = credential {
            let requested = request.scenario.requestedClaims
            let notShared = c.disclosures.map(\.key).filter { !requested.contains($0) }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VerifierHeader(scenario: request.scenario)
                    Text(settings.t("consent.wants", verifierName)).font(.gov(.headline))

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(settings.t("consent.from", settings.t(c.type.titleKey)), systemImage: c.type.icon)
                                .font(.gov(.subheadline)).foregroundStyle(.secondary)
                            ForEach(requested, id: \.self) { k in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                    Text(settings.t("claim.\(k)"))
                                    Spacer()
                                    Text(c.value(k).map { settings.display(k, $0) } ?? "—").bold()
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                    } label: { Text(settings.t("consent.willShare")) }

                    if !notShared.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(notShared, id: \.self) { k in
                                    Label(settings.t("claim.\(k)"), systemImage: "eye.slash")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        } label: { Text(settings.t("consent.notShared")) }
                    }

                    Button {
                        Task {
                            guard await Biometrics.confirm(reason: settings.t("consent.authReason")) else { return }
                            let r = store.runVerification(request: request, credential: c, attack: request.attack, offline: request.offline)
                            withAnimation { phase = .result(r) }
                        }
                    } label: {
                        Label(settings.t("consent.share"), systemImage: "faceid").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button(role: .cancel) {
                        store.logDeclined(request, type: c.type)
                        dismiss()
                    } label: {
                        Text(settings.t("consent.decline")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding()
            }
        } else {
            ContentUnavailableView(settings.t("consent.noCredential"), systemImage: "wallet.pass")
        }
    }
}

struct VerifierHeader: View {
    @EnvironmentObject private var settings: AppSettings
    let scenario: Scenario
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: scenario.icon)
                .font(.gov(.title))
                .frame(width: 56, height: 56)
                .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .foregroundStyle(Color.brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.t(scenario.verifierNameKey)).font(.gov(.title3, .bold))
                Label(settings.t("consent.verifiedOrg"), systemImage: "checkmark.seal.fill")
                    .font(.gov(.caption)).foregroundStyle(.green)
                Text(settings.t(scenario.purposeKey)).font(.gov(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }
}

struct ResultView: View {
    @EnvironmentObject private var settings: AppSettings
    let result: VerificationResult

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: result.outcome.icon)
                    .font(.system(size: 84))
                    .foregroundStyle(result.outcome.color)
                    .padding(.top, 12)
                Text(settings.t(result.outcome.titleKey)).font(.gov(.largeTitle, .bold))
                if let reason = result.outcome.reasonKey {
                    Text(settings.t(reason)).multilineTextAlignment(.center)
                }
                if case .validOffline(let asOf) = result.outcome {
                    Text(settings.t("result.offlineAsOf", settings.date(asOf, time: true)))
                        .font(.gov(.footnote)).multilineTextAlignment(.center).foregroundStyle(.orange)
                }

                GroupBox {
                    if result.disclosed.isEmpty {
                        Text(settings.t("result.nothingShared")).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(result.disclosed, id: \.key) { d in
                                LabeledContent(settings.t("claim.\(d.key)"), value: settings.display(d.key, d.value))
                            }
                        }
                    }
                } label: { Text(settings.t("result.verifierSees")) }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.checks) { c in
                            Label(settings.t(c.labelKey), systemImage: c.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(c.passed ? Color.green : Color.red)
                                .font(.gov(.subheadline))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: { Text(settings.t("result.checks")) }
            }
            .padding()
        }
        .background(result.outcome.color.opacity(0.07))
    }
}
