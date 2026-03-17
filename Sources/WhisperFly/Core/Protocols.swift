import Foundation

struct TranscriptionResultPayload: Sendable {
    let text: String
    let latency: TimeInterval
    let audioURL: URL
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

enum RewriteMode: String, Codable, Sendable, CaseIterable {
    case cleanup = "Cleanup"
    case punctuate = "Punctuate"
    case translate = "Translate to English"
    
    var localizedName: String {
        switch self {
        case .cleanup: return String(localized: "rewrite.cleanup", defaultValue: "Cleanup")
        case .punctuate: return String(localized: "rewrite.punctuate", defaultValue: "Punctuate")
        case .translate: return String(localized: "rewrite.translate", defaultValue: "Translate to English")
        }
    }
}

protocol SpeechRecognizer: Sendable {
    func transcribe(audioURL: URL) async throws -> TranscriptionResultPayload
}

protocol TextRewriter: Sendable {
    func rewrite(inputText: String, locale: Locale, mode: RewriteMode) async throws -> RewriteResultPayload
}

protocol TextInjector: Sendable {
    func insert(text: String) throws -> InsertResult
}

protocol AudioCapturing: Sendable {
    func startRecording() async throws -> URL
    func stopRecording() async throws -> URL
    func cancelRecording() async
    var onAudioLevel: (@Sendable (Float) -> Void)? { get set }
    var onMaxDurationReached: (@Sendable () -> Void)? { get set }
}

protocol HotkeyMonitoring: Sendable {
    func register() throws
    func unregister()
    var onPress: (@Sendable () -> Void)? { get set }
    var onRelease: (@Sendable () -> Void)? { get set }
}
