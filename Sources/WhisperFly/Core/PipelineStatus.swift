import Foundation

enum PipelineStatus: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case rewriting
    case pasting
    case error(String)
    
    var isProcessing: Bool {
        switch self {
        case .transcribing, .rewriting, .pasting: return true
        default: return false
        }
    }
    
    var statusText: String {
        switch self {
        case .idle: return String(localized: "status.ready", defaultValue: "Ready")
        case .recording: return String(localized: "status.recording", defaultValue: "Recording…")
        case .transcribing: return String(localized: "status.transcribing", defaultValue: "Transcribing…")
        case .rewriting: return String(localized: "status.rewriting", defaultValue: "Rewriting…")
        case .pasting: return String(localized: "status.pasting", defaultValue: "Pasting…")
        case .error(let msg): return String(format: NSLocalizedString("status.error", value: "Error: %@", comment: ""), msg)
        }
    }
    
    var iconName: String {
        switch self {
        case .idle: return "waveform"
        case .recording: return "mic.fill"
        case .transcribing: return "text.bubble"
        case .rewriting: return "sparkles"
        case .pasting: return "doc.on.clipboard"
        case .error: return "exclamationmark.triangle"
        }
    }
}
