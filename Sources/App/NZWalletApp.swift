// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

@main
struct NZWalletApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var store = WalletStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .environment(\.locale, settings.locale)
                .tint(.brand)
                .font(.gov(.body))   // default for text without an explicit font
                .lineSpacing(2)      // Public Sans sets tighter than SF
        }
    }
}

extension Color {
    static let brand = Color.nzInk
}
