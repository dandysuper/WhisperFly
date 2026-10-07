import Foundation
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "Hotkey")

/// Registers the global push-to-toggle shortcut with Carbon's hotkey API.
///
/// Carbon hot keys are used rather than `NSEvent` global monitors because they
/// fire even when another app is frontmost and, unlike an event tap, they need no
/// Accessibility grant of their own — the app already requests that separately
/// for text insertion, and tying the hotkey to it would mean the shortcut stops
/// working the moment the user revokes AX.
///
/// The previous implementation hard-coded ⌘⇧Space: `AppSettings.hotkey` was
/// presented in the settings UI and then never read, so choosing a different
/// shortcut appeared to work and changed nothing. Registration is now driven by
/// the preset it is handed.
final class HotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {

    var onPress: (@Sendable () -> Void)?
    var onRelease: (@Sendable () -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// The instance the C event callback talks to; C function pointers cannot
    /// capture context, so the active monitor is held statically.
    nonisolated(unsafe) private static var current: HotkeyMonitor?

    /// Distinguishes registrations so a hotkey the system still holds from a
    /// previous registration cannot be mistaken for the new one.
    private static let signature: OSType = 0x5746_4C57 // "WFLW"
    private var registrationCount: UInt32 = 0

    // MARK: - Registration

    func register(preset: AppSettings.HotkeyPreset) throws {
        unregister()
        Self.current = self

        registrationCount += 1
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: registrationCount)

        try installHandler()

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            preset.keyCode,
            preset.carbonModifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )

        guard status == noErr else {
            removeHandler()
            Self.current = nil
            throw HotkeyError.registrationFailed(chord: preset.displayName, status: status)
        }

        hotkeyRef = reference
        log.info("Registered hotkey \(preset.displayName, privacy: .public)")
    }

    func unregister() {
        if let reference = hotkeyRef {
            UnregisterEventHotKey(reference)
            hotkeyRef = nil
        }
        removeHandler()
        if Self.current === self {
            Self.current = nil
        }
    }

    deinit {
        if let reference = hotkeyRef {
            UnregisterEventHotKey(reference)
        }
        // `removeHandler` is not called from deinit: AppKit may already be
        // tearing down the application event target at this point.
    }

    // MARK: - Private

    private func installHandler() throws {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                switch GetEventKind(event) {
                case UInt32(kEventHotKeyPressed):
                    HotkeyMonitor.current?.onPress?()
                case UInt32(kEventHotKeyReleased):
                    HotkeyMonitor.current?.onRelease?()
                default:
                    return OSStatus(eventNotHandledErr)
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            nil,
            &handler
        )

        guard status == noErr, let handler else {
            throw HotkeyError.handlerInstallFailed(status: status)
        }
        handlerRef = handler
    }

    private func removeHandler() {
        if let handler = handlerRef {
            RemoveEventHandler(handler)
            handlerRef = nil
        }
    }

    // MARK: - Errors

    enum HotkeyError: LocalizedError {
        case handlerInstallFailed(status: OSStatus)
        case registrationFailed(chord: String, status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .handlerInstallFailed(let status):
                return L("hotkey.error.handler",
                         "The global shortcut could not be enabled (handler status %d).", status)
            case .registrationFailed(let chord, let status):
                // `eventHotKeyExistsErr` (-9878) is by far the common one: some
                // other app already owns the combination.
                if status == OSStatus(eventHotKeyExistsErr) {
                    return L("hotkey.error.taken",
                             "%@ is already used by another app. Choose a different shortcut in Settings.", chord)
                }
                return L("hotkey.error.registration",
                         "Could not register %@ (status %d). Choose a different shortcut in Settings.", chord, status)
            }
        }
    }
}
