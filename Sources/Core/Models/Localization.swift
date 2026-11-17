import Foundation

/// Localizes a Chinese source string at runtime.
///
/// SwiftUI localizes `Text("…")` on its own, but it resolves the key inside the framework and
/// ignores `Bundle.main` — so an in-app language switch only reaches the strings that come
/// through here. Every user-facing string in the UI therefore calls `L(_:)`, and the language
/// picker becomes a single published value instead of a relaunch.
///
/// A key with no translation (user data, provider names) comes back unchanged, which makes it
/// safe to call on anything.
func L(_ key: String) -> String {
    if let chosen = LanguageStore.shared.bundle {
        return chosen.localizedString(forKey: key, value: key, table: "Localizable")
    }
    return String(localized: String.LocalizationValue(key))
}

/// Same, for a key plus arguments (`%lld`, `%@`).
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
