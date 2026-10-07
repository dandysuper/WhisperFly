import Foundation
import AVFoundation
import AppKit
import ApplicationServices
import ScreenCaptureKit
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "Permissions")

/// The one place that answers "does this build hold permission X right now".
///
/// Every screen that cares — the menu bar, settings, the recording pipeline —
/// asks this object, so there is exactly one probing strategy per permission and
/// exactly one set of rules for turning a probe result into a `PermissionState`.
/// The app previously scattered that logic across `AppController` (two `Bool`s, a
/// bespoke `CGPreflightScreenCaptureAccess()` call and a `#available(macOS 26)`
/// branch) and `PasteService` (a second, different accessibility probe). The two
/// disagreed, and the `#available` branch meant the behaviour silently changed
/// with the OS version rather than with the actual permission state.
///
/// The probing rules are deliberately different per permission, because the
/// three macOS APIs are not equally trustworthy:
///
/// - **Microphone** answers synchronously and accurately. It is the only one
///   that can distinguish "never asked" from "denied", which is why it is the
///   only permission the UI offers an in-app request button for.
/// - **Screen Recording** is reachable through `CGPreflightScreenCaptureAccess()`,
///   which caches per process and has documented false negatives. The
///   authoritative source is `SCShareableContent` — the API that actually
///   performs the capture — so preflight is treated as a hint and the
///   ScreenCaptureKit call as the verdict. That is version-independent, which is
///   what the old `#available(macOS 26)` workaround failed to be.
/// - **Accessibility** is gated by `AXIsProcessTrusted()`, which caches per
///   process and can report `false` for a grant that was made minutes ago. A live
///   `AXUIElementCopyAttributeValue` on the system-wide element settles it: if the
///   AX API answers at all, the grant exists.
@MainActor
final class PermissionService: ObservableObject {

    /// Latest known state per permission. Views observe this and stay in sync
    /// without polling.
    @Published private(set) var states: [PermissionKind: PermissionState] = [:]

    /// How this build is signed, which decides whether grants survive an update.
    /// Read once: a process cannot change its own signature while running.
    let signature = CodeSignatureInfo.current()

    init() {
        // Seed with the two probes that are synchronous so the first render is
        // never empty; Screen Recording follows from `refresh` on the async path.
        states[.microphone] = Self.probeMicrophone()
        states[.accessibility] = Self.probeAccessibility()
    }

    // MARK: - Reading

    func state(for kind: PermissionKind) -> PermissionState {
        states[kind] ?? .unknown
    }

    func isGranted(_ kind: PermissionKind) -> Bool {
        state(for: kind).isGranted
    }

    /// Permissions that a check-up on app activation can update cheaply.
    var unsatisfied: [PermissionKind] {
        PermissionKind.allCases.filter { !isGranted($0) }
    }

    // MARK: - Probing

    func refreshAll() async {
        for kind in PermissionKind.allCases {
            await refresh(kind)
        }
    }

    /// Cheap re-probe for the two synchronous permissions, plus the async Screen
    /// Recording check. Called when the app becomes active, which is when the
    /// user has usually just come back from System Settings.
    func refreshOnActivation() async {
        states[.microphone] = Self.probeMicrophone()
        states[.accessibility] = Self.probeAccessibility()
        await refresh(.screenRecording)
    }

    func refresh(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            states[.microphone] = Self.probeMicrophone()
        case .accessibility:
            states[.accessibility] = Self.probeAccessibility()
        case .screenRecording:
            states[.screenRecording] = await Self.probeScreenRecording()
        }
    }

    /// `AVCaptureDevice.authorizationStatus` is synchronous and never cached
    /// beyond the current state, so this is always current.
    static func probeMicrophone() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return .granted
        case .denied:        return .denied
        case .restricted:    return .restricted
        case .notDetermined: return .notDetermined
        @unknown default:    return .unknown
        }
    }

    /// Preflight first, then let ScreenCaptureKit decide.
    ///
    /// Preflight returning `true` is conclusive. Returning `false` is not, so the
    /// capture API is asked directly — a refusal is mapped through
    /// `PermissionState(screenCaptureError:)`, and anything else (no display, a
    /// busy daemon) stays `.unknown` rather than being reported as a missing
    /// grant the user cannot actually fix.
    static func probeScreenRecording() async -> PermissionState {
        if CGPreflightScreenCaptureAccess() { return .granted }

        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            // Preflight said no but the capture API worked: preflight is wrong.
            return .granted
        } catch {
            let mapped = PermissionState(screenCaptureError: error)
            log.info("ScreenCaptureKit refused: \(String(describing: mapped), privacy: .public)")
            return mapped
        }
    }

    /// `AXIsProcessTrusted()` caches, so a live AX call breaks the tie.
    static func probeAccessibility() -> PermissionState {
        if AXIsProcessTrusted() { return .granted }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        switch AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) {
        case .success, .noValue, .attributeUnsupported, .illegalArgument:
            // The API answered, so Accessibility is enabled for this process;
            // only the trust cache is stale.
            return .granted
        case .apiDisabled, .notImplemented:
            return .denied
        default:
            return .unknown
        }
    }

    // MARK: - Requesting

    /// Asks macOS for `kind`, showing the system prompt when there is one.
    ///
    /// Accessibility and Screen Recording grants only apply to a fresh process,
    /// so callers should offer a relaunch afterwards
    /// (`PermissionKind.requiresRelaunchToTakeEffect` marks which ones).
    func request(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            states[.microphone] = Self.probeMicrophone()

        case .screenRecording:
            // Raises the prompt; macOS records the answer for the next launch.
            CGRequestScreenCaptureAccess()
            await refresh(.screenRecording)

        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            states[.accessibility] = Self.probeAccessibility()
        }
    }

    // MARK: - Repair

    /// Clears this app's TCC row for `kind` so the next prompt starts clean.
    ///
    /// This is the fix for the case the UI otherwise cannot resolve: the grant
    /// rows are matched to a designated requirement, so after a re-sign they can
    /// point at a binary that no longer exists — System Settings shows the switch
    /// on while the running process is still untrusted.
    func reset(_ kind: PermissionKind) throws {
        try PermissionRepair.reset(kind, bundleIdentifier: BuildInfo.bundleIdentifier)
        states[kind] = .notDetermined
    }

    // MARK: - System Settings

    func openSettings(for kind: PermissionKind) {
        guard let url = kind.settingsDeepLink else {
            log.error("No System Settings deep link for \(kind.rawValue, privacy: .public)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Diagnostics

    /// One-line explanation of whether the user's grants will survive the next
    /// update, or `nil` when the signature is stable.
    var signatureWarning: String? {
        signature.persistenceDiagnosis
    }
}
