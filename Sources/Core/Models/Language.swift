import Combine
import Foundation
import ObjectiveC

/// The language the interface renders in.
///
/// `.system` follows the device; the forced cases pick a table directly, which is what the in-app
/// picker sets. Every string lives in `Resources/<code>.lproj/Localizable.strings`, so adding a
/// language is a file, not a code change.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case traditionalChinese = "zh-Hant"

    var id: String { rawValue }

    /// The language's own name — a picker written in a language you cannot read is a trap.
    var nativeName: String {
        switch self {
        case .system: return L("跟隨系統")
        case .english: return "English"
        case .traditionalChinese: return "繁體中文"
        }
    }

    /// The type's own code, or the device's when following the system.
    var code: String {
        switch self {
        case .system: return Bundle.main.preferredLocalizations.first ?? "en"
        default: return rawValue
        }
    }

    /// Dates, numbers and relative times follow the same choice as the strings — otherwise the UI
    /// reads English while the timestamps stay Chinese.
    var locale: Locale {
        switch self {
        case .system: return .autoupdatingCurrent
        default: return Locale(identifier: rawValue)
        }
    }
}

/// Holds the chosen language and the bundle its strings come from.
///
/// SwiftUI resolves `Text("…")` inside its own framework and never asks `Bundle.main` for the
/// table, so the whole UI reads through `L(_:)` instead; keeping the switch here means every one
/// of those lookups lands in the same place, and a language change is one published value.
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    static let defaultsKey = "tv.language"

    @Published private(set) var language: AppLanguage

    private let defaults: UserDefaults
    private(set) var bundle: Bundle?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(rawValue: defaults.string(forKey: Self.defaultsKey) ?? "") ?? .system
        bundle = Self.bundle(for: language)
    }

    var locale: Locale { language.locale }

    func select(_ language: AppLanguage) {
        guard language != self.language else { return }
        self.language = language
        defaults.set(language.rawValue, forKey: Self.defaultsKey)
        bundle = Self.bundle(for: language)
    }

    private static func bundle(for language: AppLanguage) -> Bundle? {
        guard language != .system,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return nil }
        return bundle
    }
}

/// Feeds `NSLocalizedString` and `String(localized:)` from the chosen table, for the call sites
/// that cannot go through `L(_:)` (framework-provided titles, for instance).
///
/// `Bundle` carries no stored state here, so re-classing `Bundle.main` is safe.
final class LanguageBundle: Bundle, @unchecked Sendable {
    override func localizedString(forKey key: String, value: String?, table tableName: String?) -> String {
        guard let chosen = LanguageStore.shared.bundle else {
            return super.localizedString(forKey: key, value: value, table: tableName)
        }
        return chosen.localizedString(forKey: key, value: value, table: tableName)
    }
}

/// Call once, before the first view renders: `init` of the App type.
func installLanguageOverride() {
    object_setClass(Bundle.main, LanguageBundle.self)
}
