// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @State private var appLock = AppLockState()
    @State private var screenshotToast = false

    var body: some View {
        let unlockGeneration = appLock.generation
        ZStack {
            if appLock.isUnlocked {
                MainTabView().transition(.opacity)
            } else {
                LockView {
                    appLock.unlock(ifGenerationMatches: unlockGeneration)
                }
            }
            // Hide credentials in the app switcher (RFP §8 accidental disclosure).
            if scenePhase != .active { PrivacyShield() }
        }
        .overlay(alignment: .top) {
            if screenshotToast {
                Label(settings.t("toast.screenshot"), systemImage: "camera.metering.unknown")
                    .font(.gov(.footnote, .semibold))
                    .padding(14)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // System authentication may briefly inactivate the app. Preserve
            // that prompt, but always lock if the app actually backgrounds.
            if phase == .background || (phase == .inactive && appLock.isUnlocked && !Biometrics.isAuthenticating) {
                appLock.lock()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            withAnimation { screenshotToast = true }
            Task {
                try? await Task.sleep(for: .seconds(4))
                withAnimation { screenshotToast = false }
            }
        }
    }
}

struct PrivacyShield: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            Label(settings.t("privacy.shield"), systemImage: "eye.slash.fill").font(.gov(.headline))
        }
    }
}

struct LockView: View {
    @EnvironmentObject private var settings: AppSettings
    let onUnlock: () -> Void
    @State private var failed = false
    @State private var authenticating = false

    var body: some View {
        ZStack {
            Color.nzInk.ignoresSafeArea()
            GuillocheRosette(center: UnitPoint(x: 0.5, y: 0.3), radius: 0.32)
                .stroke(Color.nzSilver.opacity(0.12), lineWidth: 1)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer()
                NZMark(color: .nzAccent, outline: .white, lineWidth: 1.5).frame(width: 104, height: 104)
                Text(settings.t("app.name")).font(.gov(.largeTitle, .bold)).foregroundStyle(.white)
                Text(settings.t("lock.tagline"))
                    .font(.gov(.headline)).textCase(.uppercase).tracking(1)
                    .foregroundStyle(Color.nzSilver)
                Text(settings.t("lock.subtitle"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()

                Button {
                    guard !authenticating else { return }
                    authenticating = true
                    failed = false
                    Task { @MainActor in
                        defer { authenticating = false }
                        if await Biometrics.confirm(reason: settings.t("lock.reason")) { onUnlock() } else { failed = true }
                    }
                } label: {
                    Label(settings.t("lock.unlock"), systemImage: "faceid")
                        .font(.gov(.headline))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(Color.nzInk)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 4))
                }
                .disabled(authenticating)
                if failed {
                    Text(settings.t("lock.failed")).font(.gov(.footnote)).foregroundStyle(.red)
                }
                LanguagePicker().environment(\.colorScheme, .dark)
            }
            .padding(24)
        }
    }
}

struct LanguagePicker: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        Picker(settings.t("settings.language"), selection: $settings.language) {
            ForEach(AppLanguage.allCases) { Text($0.nativeName).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

struct MainTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var tab = UserDefaults.standard.string(forKey: "startTab") ?? "home"

    // Same five destinations as Service NSW: Home, Wallet, Services, Inbox, Account.
    private let tabs: [(id: String, key: String, icon: String)] = [
        ("home", "tab.home", "house.fill"),
        ("wallet", "tab.wallet", "wallet.pass.fill"),
        ("services", "tab.services", "square.grid.2x2.fill"),
        ("inbox", "tab.inbox", "tray.fill"),
        ("account", "tab.account", "person.crop.circle.fill"),
    ]

    var body: some View {
        // Flat, opaque, full-width tab bar (as in Service NSW and myVicRoads),
        // drawn by the app so it looks the same on every iOS version.
        Group {
            switch tab {
            case "wallet": WalletView()
            case "services": ServicesView()
            case "inbox": InboxView()
            case "account": SettingsView()
            default: HomeView(tab: $tab)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(tabs, id: \.id) { t in
                    let selected = tab == t.id
                    Button { tab = t.id } label: {
                        VStack(spacing: 4) {
                            Rectangle().fill(selected ? Color.nzAccent : .clear).frame(height: 3)
                            Image(systemName: t.icon).font(.system(size: 20))
                            Text(settings.t(t.key)).font(.gov(.caption2, selected ? .bold : .regular))
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(selected ? Color.nzInk : Color.govMuted)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.bottom, 2)
            .background(Color.white.ignoresSafeArea(edges: .bottom))
            .overlay(alignment: .top) { Rectangle().fill(Color.govLine).frame(height: 1) }
        }
    }
}
