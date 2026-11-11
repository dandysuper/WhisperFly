import Foundation
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "Hotkey")

/// Registers the global dictation shortcut, and Escape while a dictation is in
/// flight, with Carbon's hotkey API.
///
/// Carbon hot keys are used rather than `NSEvent` global monitors because they
/// fire even when another app is frontmost and, unlike an event tap, they need no
/// Accessibility grant of their own — the app already requests that separately
/// for text insertion, and tying the hotkey to it would mean the shortcut stops
/// working the moment the user revokes AX.
///
/// Escape is registered only while recording or transcribing, so it cancels the
/// dictation from any app and is handed back to the system the moment the
/// pipeline is idle again.
final class HotkeyMonitor: HotkeyMonitoring, @unchecked Sendable {

    var onPress: (@Sendable () -> Void)?
    var onRelease: (@Sendable () -> Void)?
    var onCancel: (@Sendable () -> Void)?

    private var hotkeyRef: EventHotKeyRef?
    private var cancelRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// The instance the C event callback talks to; C function pointers cannot
    /// capture context, so the active monitor is held statically.
    nonisolated(unsafe) private static var current: HotkeyMonitor?

    /// Distinguishes registrations so a hotkey the system still holds from a
    /// previous registration cannot be mistaken for the new one.
    private static let signature: OSType = 0x5746_4C57 // "WFLW"
    private static let cancelID: UInt32 = 0xE5C
    private var registrationCount: UInt32 = 0
    private var mainHotkeyID: UInt32 = 0

    // MARK: - Registration

    func register(preset: AppSettings.HotkeyPreset) throws {
        unregisterMainHotkey()
        Self.current = self
        try installHandlerIfNeeded()

        registrationCount += 1
        mainHotkeyID = registrationCount
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: mainHotkeyID)

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
            throw HotkeyError.registrationFailed(chord: preset.displayName, status: status)
        }

        hotkeyRef = reference
        log.info("Registered hotkey \(preset.displayName, privacy: .public)")
    }

    func registerCancelKey() {
        guard cancelRef == nil else { return }
        do { try installHandlerIfNeeded() } catch { return }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            EventHotKeyID(signature: Self.signature, id: Self.cancelID),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr {
            cancelRef = reference
        } else {
            log.info("Escape is owned by another app (status \(status)); cancel stays mouse-only")
        }
    }

    func unregisterCancelKey() {
        if let reference = cancelRef {
            UnregisterEventHotKey(reference)
            cancelRef = nil
        }
    }

    /// Releases the dictation chord but keeps the handler for Escape; used when
    /// the shortcut is Fn, which `FnKeyMonitor` watches instead.
    func unregisterShortcut() {
        unregisterMainHotkey()
        mainHotkeyID = 0
    }

    func unregister() {
        unregisterMainHotkey()
        unregisterCancelKey()
        removeHandler()
        if Self.current === self {
            Self.current = nil
        }
    }

    deinit {
        if let reference = hotkeyRef { UnregisterEventHotKey(reference) }
        if let reference = cancelRef { UnregisterEventHotKey(reference) }
        // `removeHandler` is not called from deinit: AppKit may already be
        // tearing down the application event target at this point.
    }

    // MARK: - Private

    private func unregisterMainHotkey() {
        if let reference = hotkeyRef {
            UnregisterEventHotKey(reference)
            hotkeyRef = nil
        }
    }

    private func installHandlerIfNeeded() throws {
        guard handlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]

        var handler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var hotkeyID = EventHotKeyID()
                let lookup = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                guard lookup == noErr, hotkeyID.signature == HotkeyMonitor.signature,
                      let monitor = HotkeyMonitor.current else {
                    return OSStatus(eventNotHandledErr)
                }

                let kind = GetEventKind(event)
                if hotkeyID.id == HotkeyMonitor.cancelID {
                    if kind == UInt32(kEventHotKeyPressed) { monitor.onCancel?() }
                    return noErr
                }
                guard hotkeyID.id == monitor.mainHotkeyID else { return OSStatus(eventNotHandledErr) }
                switch kind {
                case UInt32(kEventHotKeyPressed):  monitor.onPress?()
                case UInt32(kEventHotKeyReleased): monitor.onRelease?()
                default: return OSStatus(eventNotHandledErr)
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
