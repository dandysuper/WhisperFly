import Foundation
import AppKit
import Carbon

final class PasteService: TextInjector, Sendable {
    private let pasteDelayMs: Int
    
    init(pasteDelayMs: Int = 100) {
        self.pasteDelayMs = pasteDelayMs
    }
    
    func insert(text: String) throws -> InsertResult {
        if tryAccessibilityInsert(text) {
            return .accessibility
        }
        try clipboardInsert(text)
        return .clipboard
    }
    
    private func tryAccessibilityInsert(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        guard result == .success, let element = focusedElement else { return false }
        
        let axElement = element as! AXUIElement
        
        var hasValue: DarwinBoolean = false
        let isSettable = AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &hasValue)
        guard isSettable == .success, hasValue.boolValue else { return false }
        
        let setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, text as CFTypeRef)
        return setResult == .success
    }
    
    private func clipboardInsert(_ text: String) throws {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)
        
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)  // V key
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        // Restore clipboard after delay
        let delay = pasteDelayMs
        let old = oldContents
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay + 100)) {
            if let old {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }
}
