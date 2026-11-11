import Foundation

/// A spoken language the user can pin, or automatic detection.
///
/// Stored settings keep the ISO-639-1 code (`"en"`, `"ru"`, …) so values written
/// by earlier releases stay valid. Each engine wants a slightly different
/// spelling, which is why the mapping lives here rather than in every client.
struct DictationLanguage: Identifiable, Hashable, Sendable {
    let code: String
    /// BCP-47 tag Gemini 3.5 Transcribe expects (`language_codes`).
    let geminiCode: String?

    var id: String { code }

    static let autoCode = "auto"

    var isAuto: Bool { code == Self.autoCode }

    /// Name in the user's UI language, e.g. "Russian" / "русский".
    var localizedName: String {
        if isAuto { return L("lang.auto", "Auto-detect") }
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// English name, used inside prompts so the model is never confused by a
    /// localized language name.
    var englishName: String {
        if isAuto { return "the speaker's language" }
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    /// ISO-639-1 code accepted by Whisper (`language` form field).
    var whisperCode: String? {
        if isAuto { return nil }
        switch code {
        case "nb": return "no"
        default:   return code
        }
    }

    static let all: [DictationLanguage] = [
        .init(code: autoCode, geminiCode: nil),
        .init(code: "en", geminiCode: "en-US"),
        .init(code: "ru", geminiCode: "ru-RU"),
        .init(code: "uk", geminiCode: "uk-UA"),
        .init(code: "kk", geminiCode: "kk-KZ"),
        .init(code: "de", geminiCode: "de-DE"),
        .init(code: "fr", geminiCode: "fr-FR"),
        .init(code: "es", geminiCode: "es-US"),
        .init(code: "it", geminiCode: "it-IT"),
        .init(code: "pt", geminiCode: "pt-BR"),
        .init(code: "nl", geminiCode: "nl-NL"),
        .init(code: "pl", geminiCode: "pl-PL"),
        .init(code: "tr", geminiCode: "tr-TR"),
        .init(code: "ja", geminiCode: "ja-JP"),
        .init(code: "zh", geminiCode: "cmn-Hans-CN"),
        .init(code: "ko", geminiCode: "ko-KR"),
        .init(code: "hi", geminiCode: "hi-IN"),
        .init(code: "ar", geminiCode: "ar-EG"),
        .init(code: "he", geminiCode: "he-IL"),
        .init(code: "sv", geminiCode: "sv-SE"),
        .init(code: "nb", geminiCode: "nb-NO"),
        .init(code: "da", geminiCode: "da-DK"),
        .init(code: "fi", geminiCode: "fi-FI"),
        .init(code: "cs", geminiCode: "cs-CZ"),
        .init(code: "ro", geminiCode: "ro-RO"),
        .init(code: "hu", geminiCode: "hu-HU"),
        .init(code: "el", geminiCode: "el-GR"),
        .init(code: "bg", geminiCode: "bg-BG"),
        .init(code: "id", geminiCode: "id-ID"),
        .init(code: "vi", geminiCode: "vi-VN"),
        .init(code: "th", geminiCode: "th-TH"),
    ]

    /// Languages that make sense as a translation target (no auto-detect).
    static var translationTargets: [DictationLanguage] {
        all.filter { !$0.isAuto }
    }

    static func lookup(_ code: String) -> DictationLanguage {
        all.first { $0.code == code } ?? DictationLanguage(code: code, geminiCode: nil)
    }
}
