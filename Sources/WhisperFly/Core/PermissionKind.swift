import Foundation

/// The three TCC-protected capabilities WhisperFly relies on.
///
/// Each case knows how macOS names the service and which System Settings pane
/// owns it, so the UI never hard-codes a deep link in more than one place.
/// This type is the single definition every permission-related file shares —
/// the previous code compared a `startIndex` against a `pickerIndex` to guess
/// which permission was meant, which is why a hotkey conflict could silently
/// report the wrong permission as missing.
enum PermissionKind: String, CaseIterable, Sendable, Identifiable {
    case microphone
    case screenRecording
    case accessibility

    var id: String { rawValue }

    /// The identifier `tccutil(1)` expects for `tccutil reset <service>`.
    var tccServiceName: String {
        switch self {
        case .microphone:      return "Microphone"
        case .screenRecording: return "ScreenCapture"
        case .accessibility:   return "Accessibility"
        }
    }

    /// `true` when macOS only re-reads the grant after the process restarts.
    ///
    /// Microphone is answered through a live API prompt, so the result is known
    /// immediately. Screen Recording is cached by the TCC daemon for the lifetime
    /// of most processes, so a relaunch is the only reliable way to pick up a
    /// newly flipped switch.
    var requiresRelaunchToTakeEffect: Bool {
        switch self {
        case .microphone:      return false
        case .screenRecording: return true
        case .accessibility:   return false
        }
    }

    /// Deep link into the matching Privacy pane in System Settings.
    var settingsDeepLink: URL? {
        let host = "x-apple.systempreferences:com.apple.preference.security"
        let query: String
        switch self {
        case .microphone:      query = "Privacy_Microphone"
        case .screenRecording: query = "Privacy_ScreenCapture"
        case .accessibility:   query = "Privacy_Accessibility"
        }
        return URL(string: "\(host)?\(query)")
    }

    var title: String {
        switch self {
        case .microphone:      return L("permission.microphone", "Microphone")
        case .screenRecording: return L("permission.screen_recording", "Screen Recording")
        case .accessibility:   return L("permission.accessibility", "Accessibility")
        }
    }

    var purpose: String {
        switch self {
        case .microphone:
            return L("permission.microphone.purpose",
                     "Records your voice when the microphone source is selected.")
        case .screenRecording:
            return L("permission.screen_recording.purpose",
                     "Lets ScreenCaptureKit capture system audio. macOS gates all ScreenCaptureKit access behind this switch.")
        case .accessibility:
            return L("permission.accessibility.purpose",
                     "Types the transcription into the focused app and positions the status pill next to the caret.")
        }
    }

    var systemImage: String {
        switch self {
        case .microphone:      return "mic.fill"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .accessibility:   return "lock.shield.fill"
        }
    }
}
