import Foundation

// MARK: - Localized copy outside SwiftUI
//
// SwiftUI `Text("…")` picks up Localizable.xcstrings automatically.
// Notifications, analytics labels and dynamic `String` formatting use this.

enum L10n {
    static func s(_ key: String.LocalizationValue) -> String {
        String(localized: key)
    }

    static func s(_ key: String.LocalizationValue, _ args: CVarArg...) -> String {
        String(format: String(localized: key), locale: .current, arguments: args)
    }
}
