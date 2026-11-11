import Foundation

enum PipelineStatus: Sendable, Equatable {
    case idle
    case recording
    case transcribing
    case rewriting
    case pasting
    /// The text was delivered; shown briefly before returning to `idle`.
    case done(Delivery)
    case error(String)

    enum Delivery: Sendable, Equatable {
        /// Typed into the app that was focused when recording started.
        case inserted
        /// Placed on the clipboard (system audio, files, or no Accessibility).
        case copied
    }

    /// Network or post-processing work is in flight.
    var isProcessing: Bool {
        switch self {
        case .transcribing, .rewriting, .pasting: return true
        default: return false
        }
    }

    /// Anything the user can cancel.
    var isBusy: Bool {
        self == .recording || isProcessing
    }

    /// A new recording may start. Errors and the "done" flash never block the
    /// hotkey — previously an error left the app deaf to the shortcut until the
    /// user found and pressed "Dismiss" in the menu.
    var canStartRecording: Bool {
        switch self {
        case .idle, .done, .error: return true
        default: return false
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:              return L("status.ready", "Ready")
        case .recording:         return L("status.recording", "Recording…")
        case .transcribing:      return L("status.transcribing", "Transcribing…")
        case .rewriting:         return L("status.rewriting", "Rewriting…")
        case .pasting:           return L("status.pasting", "Pasting…")
        case .done(.inserted):   return L("status.inserted", "Inserted")
        case .done(.copied):     return L("status.copied", "Copied to clipboard")
        case .error(let msg):    return L("status.error", "Error: %@", msg)
        }
    }

    /// Menu bar symbol.
    var iconName: String {
        switch self {
        case .idle:         return "waveform"
        case .recording:    return "waveform.circle.fill"
        case .transcribing: return "ellipsis.bubble"
        case .rewriting:    return "sparkles"
        case .pasting:      return "doc.on.clipboard"
        case .done:         return "checkmark.circle"
        case .error:        return "exclamationmark.triangle"
        }
    }
}
