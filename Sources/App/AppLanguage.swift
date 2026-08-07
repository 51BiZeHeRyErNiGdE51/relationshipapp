import SwiftUI

// MARK: - App language
//
// Missuo ships in English (default), French, German, Korean, Portuguese and
// Spanish via Resources/Localizable.xcstrings. iOS picks the system language
// automatically and falls back to English for anything else.
//
// The in-app picker (tutorial header + Us → Settings) writes the standard
// AppleLanguages override — the same mechanism as iOS Settings → Missuo →
// Language — which takes effect on the next launch. That's the only
// Apple-supported way to switch language; live in-process switching would
// require private bundle swizzling.

enum AppLanguage: String, CaseIterable, Identifiable {
    case en, fr, de, ko, pt, es

    var id: String { rawValue }

    var nativeName: String {
        switch self {
        case .en: "English"
        case .fr: "Français"
        case .de: "Deutsch"
        case .ko: "한국어"
        case .pt: "Português"
        case .es: "Español"
        }
    }

    var flag: String {
        switch self {
        case .en: "🇬🇧"
        case .fr: "🇫🇷"
        case .de: "🇩🇪"
        case .ko: "🇰🇷"
        case .pt: "🇵🇹"
        case .es: "🇪🇸"
        }
    }

    /// Shown (in the *newly chosen* language) after picking — the switch
    /// applies on next launch.
    var restartMessage: String {
        switch self {
        case .en: "Missuo will switch to English the next time you open it."
        case .fr: "Missuo passera au français à la prochaine ouverture."
        case .de: "Missuo wechselt beim nächsten Öffnen zu Deutsch."
        case .ko: "다음에 Missuo를 열면 한국어로 표시됩니다."
        case .pt: "O Missuo mudará para português na próxima vez que o abrir."
        case .es: "Missuo cambiará a español la próxima vez que lo abras."
        }
    }

    /// The language the app is actually running in right now.
    static var current: AppLanguage {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return AppLanguage(rawValue: String(code.prefix(2))) ?? .en
    }

    static func select(_ language: AppLanguage) {
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
    }
}

/// Globe menu used in the tutorial header and in Settings.
struct LanguageMenu: View {
    /// Compact = icon only (tutorial header); otherwise a labelled row.
    var compact = true
    @State private var pendingRestart: AppLanguage?

    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    guard language != AppLanguage.current else { return }
                    AppLanguage.select(language)
                    pendingRestart = language
                } label: {
                    if language == AppLanguage.current {
                        Label("\(language.flag) \(language.nativeName)", systemImage: "checkmark")
                    } else {
                        Text("\(language.flag) \(language.nativeName)")
                    }
                }
            }
        } label: {
            if compact {
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(Lovio.Palette.plum)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.ultraThinMaterial))
            } else {
                HStack {
                    Label("Language", systemImage: "globe")
                    Spacer()
                    Text("\(AppLanguage.current.flag) \(AppLanguage.current.nativeName)")
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
        }
        .alert(pendingRestart?.restartMessage ?? "",
               isPresented: .init(get: { pendingRestart != nil },
                                  set: { if !$0 { pendingRestart = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }
}
