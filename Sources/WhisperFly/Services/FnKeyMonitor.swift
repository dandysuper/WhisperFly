import AppKit
import Carbon.HIToolbox
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "FnKey")

/// Watches the Fn (🌐) key on its own, for Fn-only dictation.
///
/// Carbon's `RegisterEventHotKey` needs a real key, so a lone modifier like Fn
/// is observed through `flagsChanged` events instead. Global key-event monitors
/// only receive events once the app is trusted for Accessibility — which
/// WhisperFly already needs to type text — and a local monitor covers the case
/// where WhisperFly itself is frontmost.
///
/// Fn is also a modifier (Fn+Delete, Fn+arrows, Fn+F-keys). Any other key or
/// modifier pressed while Fn is down marks the press as a chord: `onChord`
/// fires and the release reports it, so those shortcuts keep working without
/// leaving a recording behind.
@MainActor
final class FnKeyMonitor {

    var onPress: (() -> Void)?
    /// `wasChord` is `true` when another key was pressed while Fn was held.
    var onRelease: ((_ wasChord: Bool) -> Void)?
    /// Fn turned out to be part of a key combination.
    var onChord: (() -> Void)?

    private var monitors: [Any] = []
    private var isFnDown = false
    private var isChord = false
    /// Whether the monitors were installed while the process was trusted for
    /// Accessibility. Monitors installed before the grant never see global key
    /// events, so they are reinstalled once it arrives.
    private(set) var installedWhileTrusted = false

    var isRunning: Bool { !monitors.isEmpty }

    /// Key codes the Fn / Globe key reports in `flagsChanged`.
    private static let fnKeyCodes: Set<UInt16> = [UInt16(kVK_Function), 179]
    private static let otherModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    func start() {
        guard monitors.isEmpty else { return }
        installedWhileTrusted = AXIsProcessTrusted()

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
        }) { monitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handleFlags(event) }
            return event
        }) { monitors.append(local) }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.markChord() }
        }) { monitors.append(global) }

        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.markChord() }
            return event
        }) { monitors.append(local) }

        log.info("Fn monitor started (trusted: \(self.installedWhileTrusted))")
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        isFnDown = false
        isChord = false
    }

    /// Reinstalls the monitors if Accessibility was granted after they started.
    func restartIfTrustChanged() {
        guard isRunning, !installedWhileTrusted, AXIsProcessTrusted() else { return }
        stop()
        start()
    }

    // MARK: - Events

    private func handleFlags(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        guard Self.fnKeyCodes.contains(event.keyCode) else {
            // Another modifier changed while Fn is held: a chord such as Fn+⌘.
            if isFnDown && !flags.intersection(Self.otherModifiers).isEmpty { markChord() }
            return
        }

        let fnPressed = flags.contains(.function)
        if fnPressed && !isFnDown {
            isFnDown = true
            // Fn added on top of a held modifier is a chord from the start.
            isChord = !flags.intersection(Self.otherModifiers).isEmpty
            if !isChord { onPress?() }
        } else if !fnPressed && isFnDown {
            isFnDown = false
            let wasChord = isChord
            isChord = false
            onRelease?(wasChord)
        }
    }

    private func markChord() {
        guard isFnDown, !isChord else { return }
        isChord = true
        onChord?()
    }
}

/// What macOS itself does when the Fn / 🌐 key is pressed
/// (System Settings → Keyboard → "Press 🌐 key to").
///
/// Anything other than "Do Nothing" fires alongside WhisperFly — the emoji
/// picker opening on every dictation, or the input source switching.
enum SystemFnKeyAction: Equatable {
    case doNothing
    case changeInputSource
    case showEmoji
    case startDictation
    /// Never changed in System Settings; macOS applies its own default.
    case systemDefault

    static var current: SystemFnKeyAction {
        let defaults = UserDefaults(suiteName: "com.apple.HIToolbox")
        guard let value = defaults?.object(forKey: "AppleFnUsageType") as? Int else { return .systemDefault }
        switch value {
        case 0:  return .doNothing
        case 1:  return .changeInputSource
        case 2:  return .showEmoji
        case 3:  return .startDictation
        default: return .systemDefault
        }
    }

    var conflictsWithDictation: Bool { self != .doNothing }

    var conflictDescription: String {
        switch self {
        case .doNothing:
            return ""
        case .changeInputSource:
            return L("fn.conflict.input_source", "macOS also switches the input source when you press fn.")
        case .showEmoji:
            return L("fn.conflict.emoji", "macOS also opens the emoji picker when you press fn.")
        case .startDictation:
            return L("fn.conflict.dictation", "macOS also starts its own Dictation when you press fn.")
        case .systemDefault:
            return L("fn.conflict.default", "macOS may also act on the fn key (emoji picker or input source).")
        }
    }

    static let keyboardSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
}
