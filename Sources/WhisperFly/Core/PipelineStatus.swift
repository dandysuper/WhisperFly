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
        case .idle: return "Ready"
        case .recording: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .rewriting: return "Rewriting…"
        case .pasting: return "Pasting…"
        case .error(let msg): return "Error: \(msg)"
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
