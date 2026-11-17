// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", maori = "mi"
    var id: String { rawValue }
    var nativeName: String { self == .english ? "English" : "Te reo Māori" }
}

/// App-wide settings. Language switches instantly in-app (no restart) by
/// loading strings from the matching .lproj bundle.
/// Translators only touch Resources/<lang>.lproj/Localizable.strings.
final class AppSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            bundle = Self.bundle(for: language)
        }
    }
    @Published var hideSensitive: Bool {
        didSet { UserDefaults.standard.set(hideSensitive, forKey: "hideSensitive") }
    }
    private var bundle: Bundle

    init() {
        let d = UserDefaults.standard
        // English by default; te reo Māori selectable at any time.
        let lang = d.string(forKey: "appLanguage").flatMap(AppLanguage.init) ?? .english
        language = lang
        bundle = Self.bundle(for: lang)
        hideSensitive = d.object(forKey: "hideSensitive") as? Bool ?? true
    }

    private static func bundle(for l: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: l.rawValue, ofType: "lproj"),
              let b = Bundle(path: path) else { return .main }
        return b
    }

    func t(_ key: String) -> String { bundle.localizedString(forKey: key, value: key, table: nil) }
    func t(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: locale, arguments: args) }

    var locale: Locale { Locale(identifier: language == .english ? "en_NZ" : "mi_NZ") }

    func date(_ d: Date, time: Bool = false) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.dateStyle = .medium
        f.timeStyle = time ? .short : .none
        return f.string(from: d)
    }

    /// Human-readable value for a claim in the current language.
    func display(_ key: String, _ value: String) -> String {
        switch value {
        case "true": return t("common.yes")
        case "false": return t("common.no")
        default: break
        }
        if key == "sex" { return t("sex.\(value)") }
        if key == "conditions" { return t("cond.\(value)") }
        if key == "endorsements", value == "none" { return t("cond.none") }
        if key == "dateOfBirth" {
            let iso = DateFormatter()
            iso.locale = Locale(identifier: "en_US_POSIX")
            iso.dateFormat = "yyyy-MM-dd"
            if let d = iso.date(from: value) { return date(d) }
        }
        return value
    }

    func claimList(_ keys: [String]) -> String {
        keys.map { k in let v = t("claim.\(k)"); return v == "claim.\(k)" ? t("el.\(k)") : v }.joined(separator: ", ")
    }
}
