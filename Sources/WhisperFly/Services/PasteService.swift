import Foundation
import AppKit
import ApplicationServices
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "PasteService")

final class PasteService: TextInjector, Sendable {
    private let pasteDelayMs: Int

    init(pasteDelayMs: Int = 120) {
        self.pasteDelayMs = pasteDelayMs
    }

    func insert(text: String, targetPID: pid_t? = nil) throws -> InsertResult {
        log.info("insert() called, text length=\(text.count), targetPID=\(targetPID.map { String($0) } ?? "nil")")

        // Quick check: is accessibility actually working right now?
        let axWorking = Self.isAccessibilityWorking()
        log.info("Accessibility working: \(axWorking)")

        if axWorking, tryAccessibilityInsert(text) {
            log.info("✅ Accessibility insert succeeded")
            return .accessibility
        }

        log.info("Accessibility insert \(axWorking ? "failed" : "unavailable"), falling back to clipboard")
        try clipboardInsert(text, targetPID: targetPID)
        return .clipboard
    }

    /// Live probe: can we actually make AX calls right now?
    static func isAccessibilityWorking() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedRef
        )
        // .success or .noValue both mean AX is functional.
        return status == .success || status == .noValue
    }

    // MARK: - Accessibility Insert

    /// Attempts to insert via Accessibility API. Returns true only if we are
    /// confident the text was actually written into a real text field (not a
    /// random UI element that happens to accept AX calls).
    private func tryAccessibilityInsert(_ text: String) -> Bool {
        guard let element = focusedElement() else {
            log.warning("No focused element found")
            return false
        }

        // Verify the focused element is actually a text input by checking its role.
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        log.info("Focused element role: \(role)")

        // Only proceed with AX insert for known text input roles.
        let textRoles: Set<String> = [
            kAXTextFieldRole as String,
            kAXTextAreaRole as String,
            kAXComboBoxRole as String,
            "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"
        ]
        guard textRoles.contains(role) else {
            log.info("Focused element role '\(role)' is not a text input — skipping AX insert")
            return false
        }

        // Try the simple kAXSelectedTextAttribute approach first — it works on
        // most standard text fields and correctly replaces the selection / inserts
        // at the caret without us having to splice strings.
        if trySelectedTextInsert(element, text: text) {
            log.info("✅ kAXSelectedTextAttribute insert succeeded")
            return true
        }

        // Full splice approach: read value + range, replace, write back.
        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        let rangeStatus = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef)

        guard valueStatus == .success,
              rangeStatus == .success,
              let currentValue = valueRef as? String else {
            log.warning("Cannot read value/range (value=\(valueStatus.rawValue), range=\(rangeStatus.rawValue))")
            return false
        }

        let range = selectedTextRange(from: rangeRef)
        guard let range else {
            log.warning("Cannot parse selection range")
            return false
        }

        let nsValue = currentValue as NSString
        let replacementRange = NSRange(location: range.location, length: range.length)
        guard replacementRange.location != NSNotFound,
              replacementRange.location <= nsValue.length,
              replacementRange.location + replacementRange.length <= nsValue.length else {
            log.warning("Range out of bounds: loc=\(range.location) len=\(range.length) value.len=\(nsValue.length)")
            return false
        }

        let updated = nsValue.replacingCharacters(in: replacementRange, with: text)
        let setValueStatus = AXUIElementSetAttributeValue(
            element, kAXValueAttribute as CFString, updated as CFTypeRef
        )
        guard setValueStatus == .success else {
            log.warning("kAXValueAttribute set failed: \(setValueStatus.rawValue)")
            return false
        }

        // Reposition cursor to end of inserted text.
        var newRange = CFRange(
            location: replacementRange.location + (text as NSString).length,
            length: 0
        )
        if let newRangeValue = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(
                element, kAXSelectedTextRangeAttribute as CFString, newRangeValue
            )
        }

        log.info("✅ kAXValueAttribute splice succeeded")
        return true
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject
        )
        guard focusedStatus == .success, let focusedObject else {
            log.warning("AXFocusedUIElement failed: \(focusedStatus.rawValue)")
            return nil
        }
        return (focusedObject as! AXUIElement)
    }

    private func selectedTextRange(from rangeRef: CFTypeRef?) -> CFRange? {
        guard let rangeRef else { return nil }
        guard CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        let rangeValue = rangeRef as! AXValue

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Simpler fallback: sets kAXSelectedTextAttribute directly (replaces selection / inserts at caret).
    private func trySelectedTextInsert(_ element: AXUIElement, text: String) -> Bool {
        var hasValue: DarwinBoolean = false
        let isSettable = AXUIElementIsAttributeSettable(
            element, kAXSelectedTextAttribute as CFString, &hasValue
        )
        guard isSettable == .success, hasValue.boolValue else {
            log.info("kAXSelectedTextAttribute not settable")
            return false
        }
        let setResult = AXUIElementSetAttributeValue(
            element, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        if setResult != .success {
            log.warning("kAXSelectedTextAttribute set failed: \(setResult.rawValue)")
        }
        return setResult == .success
    }

    // MARK: - Clipboard Insert

    /// Paste via clipboard + simulated Cmd+V. Always targets the specific PID when
    /// available so the keystroke is delivered to the correct process.
    func clipboardInsert(_ text: String, targetPID: pid_t? = nil) throws {
        log.info("clipboardInsert: text length=\(text.count), pid=\(targetPID.map { String($0) } ?? "nil")")
        let pasteboard = NSPasteboard.general

        // Snapshot ALL pasteboard item types so we restore rich content (images, RTF, etc.)
        let originalItems: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.compactMap { item in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot.isEmpty ? nil : snapshot
        } ?? []

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw NSError(domain: "PasteService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Unable to write text to clipboard."])
        }

        var posted = false

        // Try CGEvent first — this is the most reliable when accessibility is granted.
        if let src = CGEventSource(stateID: .combinedSessionState) {
            let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)   // kVK_ANSI_V
            let keyUp   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags   = .maskCommand

            if let pid = targetPID {
                log.info("Posting Cmd+V to PID \(pid)")
                keyDown?.postToPid(pid)
                keyUp?.postToPid(pid)
            } else {
                log.info("Posting Cmd+V to HID tap")
                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }
            posted = true
        }

        // If CGEventSource creation failed (no accessibility), use AppleScript keystroke
        // which goes through System Events and may work with just Automation permission.
        if !posted {
            log.info("CGEventSource unavailable, using AppleScript Cmd+V fallback")
            let script = NSAppleScript(source: """
                tell application "System Events" to keystroke "v" using command down
                """)
            var errorDict: NSDictionary?
            script?.executeAndReturnError(&errorDict)
            if let err = errorDict {
                log.error("AppleScript fallback failed: \(err)")
            } else {
                log.info("✅ AppleScript Cmd+V sent")
            }
        }

        // Restore clipboard after the paste has been consumed.
        let delay = pasteDelayMs
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay + 200)) {
            guard !originalItems.isEmpty else { return }
            pasteboard.clearContents()
            for snapshot in originalItems {
                let item = NSPasteboardItem()
                for (type, data) in snapshot {
                    item.setData(data, forType: type)
                }
                pasteboard.writeObjects([item])
            }
        }
        log.info("✅ clipboardInsert completed, restore scheduled in \(delay + 200)ms")
    }
}
