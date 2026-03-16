import AppKit
import SwiftUI

@MainActor
final class FloatingPanel {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingStatusView>?
    
    func show(with controller: AppController) {
        if panel != nil { updatePosition(); return }
        
        let view = FloatingStatusView(controller: controller)
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 180, height: 40)
        
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isMovableByWindowBackground = false
        p.contentView = hosting
        
        self.panel = p
        self.hostingView = hosting
        
        updatePosition()
        p.orderFrontRegardless()
    }
    
    func hide() {
        panel?.orderOut(nil)
        panel = nil
        hostingView = nil
    }
    
    private func updatePosition() {
        guard let panel else { return }
        
        // Try to position near the focused text field using Accessibility
        if let caretPos = getCaretPosition() {
            let panelOrigin = NSPoint(
                x: caretPos.x + 8,
                y: caretPos.y - 50
            )
            panel.setFrameOrigin(panelOrigin)
            return
        }
        
        // Fallback: center-bottom of the main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
    
    private func getCaretPosition() -> NSPoint? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            return nil
        }
        
        let element = focusedElement as! AXUIElement
        
        // Try to get the selected text range position
        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            return nil
        }
        
        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRange!, &bounds) == .success else {
            return nil
        }
        
        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else {
            return nil
        }
        
        // Convert from screen coordinates (top-left origin) to AppKit (bottom-left origin)
        if let screen = NSScreen.main {
            let flippedY = screen.frame.height - rect.origin.y - rect.height
            return NSPoint(x: rect.origin.x, y: flippedY)
        }
        
        return NSPoint(x: rect.origin.x, y: rect.origin.y)
    }
}
