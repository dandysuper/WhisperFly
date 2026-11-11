import Foundation

struct TranscriptionResultPayload: Sendable {
    let text: String
    let latency: TimeInterval
    let audioURL: URL
    /// Human-readable engine that produced the text, e.g. `Groq · Whisper Large v3 Turbo`.
    var providerName: String = ""
    /// `true` when the engine already removed filler words and applied
    /// formatting, so a Cleanup rewrite would only repeat the same work.
    var isAlreadyPolished: Bool = false
}

struct RewriteResultPayload: Sendable {
    let sourceText: String
    let rewrittenText: String
    let latency: TimeInterval
}

enum InsertResult: Sendable {
    case accessibility
    case clipboard
}

/// What the optional AI pass does to a finished transcript.
///
/// Raw values are persisted identifiers. `translate` keeps its historical
/// `"Translate to English"` value so existing preferences still decode; the
/// target language itself is now a separate setting.
enum RewriteMode: String, Codable, Sendable, CaseIterable, Identifiable {
    case cleanup = "Cleanup"
    case punctuate = "Punctuate"
    case professional = "Professional"
    case translate = "Translate to English"
    case custom = "Custom"

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .cleanup:      return L("rewrite.cleanup", "Cleanup")
        case .punctuate:    return L("rewrite.punctuate", "Punctuate")
        case .professional: return L("rewrite.professional", "Professional")
        case .translate:    return L("rewrite.translate_short", "Translate")
        case .custom:       return L("rewrite.custom", "Custom")
        }
    }

    var summary: String {
        switch self {
        case .cleanup:
            return L("rewrite.cleanup.summary", "Fixes grammar, removes filler words and applies spoken corrections.")
        case .punctuate:
            return L("rewrite.punctuate.summary", "Adds punctuation and capitals without changing a single word.")
        case .professional:
            return L("rewrite.professional.summary", "Turns dictation into clear, concise work-ready prose.")
        case .translate:
            return L("rewrite.translate.summary", "Translates what you said into your target language.")
        case .custom:
            return L("rewrite.custom.summary", "Follows your own instructions.")
        }
    }

    var systemImage: String {
        switch self {
        case .cleanup:      return "wand.and.stars"
        case .punctuate:    return "textformat"
        case .professional: return "briefcase.fill"
        case .translate:    return "globe"
        case .custom:       return "slider.horizontal.3"
        }
    }
}

protocol SpeechRecognizer: Sendable {
    var provider: AIProvider { get }
    /// Shown in the UI and stored in history, e.g. `Groq · whisper-large-v3-turbo`.
    var displayName: String { get }
    /// Largest upload the service accepts; bigger audio is compressed first.
    var maxUploadBytes: Int { get }
    func transcribe(audio: PreparedAudio) async throws -> TranscriptionResultPayload
}

protocol TextRewriter: Sendable {
    var provider: AIProvider { get }
    var displayName: String { get }
    /// Rewrites `inputText` following `systemPrompt` (see `RewritePrompts`).
    func rewrite(inputText: String, systemPrompt: String) async throws -> RewriteResultPayload
}

protocol TextInjector: Sendable {
    func insert(text: String, targetPID: pid_t?) throws -> InsertResult
}

protocol AudioCapturing: Sendable {
    func startRecording() async throws -> URL
    func stopRecording() async throws -> URL
    func cancelRecording() async
    var onAudioLevel: (@Sendable (Float) -> Void)? { get set }
    var onMaxDurationReached: (@Sendable () -> Void)? { get set }
}

protocol HotkeyMonitoring: Sendable {
    /// Registers `preset` as the global shortcut, replacing any previous one.
    func register(preset: AppSettings.HotkeyPreset) throws
    /// Temporarily claims Escape so a recording can be cancelled from any app.
    func registerCancelKey()
    func unregisterCancelKey()
    func unregister()
    var onPress: (@Sendable () -> Void)? { get set }
    var onRelease: (@Sendable () -> Void)? { get set }
    var onCancel: (@Sendable () -> Void)? { get set }
}
