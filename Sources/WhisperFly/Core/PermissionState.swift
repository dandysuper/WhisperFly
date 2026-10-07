import Foundation
import ScreenCaptureKit

/// Outcome of a permission probe.
///
/// `denied` and `notDetermined` are deliberately distinct: a permission that has
/// never been requested can be granted with a single API call and no trip to
/// System Settings, while a denied one can only be fixed there. Collapsing them
/// into one "not granted" flag — which is what the previous
/// `accessibilityGranted: Bool` / `screenRecordingGranted: Bool` pair did — is
/// why the app could not tell the user what to actually do.
enum PermissionState: Equatable, Sendable {
    /// macOS confirmed the capability is available to this process.
    case granted
    /// A TCC row exists for this app but the switch is off.
    case denied
    /// Never requested; the in-app request will show the system prompt.
    case notDetermined
    /// Blocked by policy (MDM profile, parental controls) — the user cannot change it.
    case restricted
    /// The probe could not produce an answer (no display, daemon busy, …).
    case unknown

    var isGranted: Bool { self == .granted }

    var label: String {
        switch self {
        case .granted:       return L("permission.state.granted", "Granted")
        case .denied:        return L("permission.state.denied", "Denied")
        case .notDetermined: return L("permission.state.not_determined", "Not requested")
        case .restricted:    return L("permission.state.restricted", "Blocked by policy")
        case .unknown:       return L("permission.state.unknown", "Unknown")
        }
    }

    /// Maps a ScreenCaptureKit failure onto a permission state.
    ///
    /// Only the `SCStreamErrorCode` values that genuinely mean "the system would
    /// not let you capture" are treated as `.denied`; everything else stays
    /// `.unknown` so a transient failure never masquerades as a missing grant.
    /// `failedToStartAudioCapture` is included deliberately — on macOS 15 and
    /// later that is the code macOS returns when Screen Recording has not been
    /// granted, not `userDeclined`.
    init(screenCaptureError error: any Error) {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain,
              let code = SCStreamError.Code(rawValue: nsError.code) else {
            self = .unknown
            return
        }
        switch code {
        case .userDeclined,
             .missingEntitlements,
             .failedToStartAudioCapture,
             .noCaptureSource,
             .noDisplayList:
            self = .denied
        default:
            self = .unknown
        }
    }

    /// A short, user-facing explanation of why a ScreenCaptureKit call failed.
    static func screenCaptureDiagnostic(for error: any Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == SCStreamErrorDomain,
              let code = SCStreamError.Code(rawValue: nsError.code) else {
            return nsError.localizedDescription
        }
        switch code {
        case .userDeclined:
            return L("screen.error.user_declined", "Screen Recording access was declined.")
        case .missingEntitlements:
            return L("screen.error.missing_entitlements",
                     "This build is missing the Screen Recording entitlement macOS requires.")
        case .failedToStartAudioCapture:
            return L("screen.error.audio_capture",
                     "macOS refused to start audio capture — Screen Recording permission is not granted for this build.")
        case .failedToStartMicrophoneCapture:
            return L("screen.error.mic_capture", "macOS refused to start microphone capture.")
        case .noCaptureSource, .noDisplayList:
            return L("screen.error.no_source", "No capturable display was reported by the system.")
        default:
            return nsError.localizedDescription
        }
    }
}
