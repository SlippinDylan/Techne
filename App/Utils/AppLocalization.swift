import Foundation

nonisolated func AppLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

nonisolated func AppLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: AppLocalized(key), locale: Locale.current, arguments: arguments)
}
