import AppKit
import SwiftUI

@MainActor
final class FloatingPanel {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<FloatingStatusView>?

    func show(with controller: AppController) {
        if let existing = panel {
            // Reuse the existing panel — just reposition and bring to front.
            // Never recreate: releasing NSPanel while a layout pass is still in
            // flight triggers EXC_BREAKPOINT (_postWindowNeedsUpdateConstraints)
            // on macOS 26 (Tahoe).
            updatePosition()
            existing.orderFrontRegardless()
            return
        }

        // First-time creation
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
        p.isReleasedWhenClosed = false
        p.contentView = hosting

        self.panel = p
        self.hostingView = hosting

        updatePosition()
        p.orderFrontRegardless()
    }

    /// Hides the panel without releasing it.
    ///
    /// We intentionally keep `panel` alive indefinitely.  Releasing an NSPanel
    /// while AppKit still has a deferred layout pass pending causes an
    /// EXC_BREAKPOINT crash inside `_postWindowNeedsUpdateConstraints` on
    /// macOS 26.  `orderOut` is sufficient to remove the panel from the screen;
    /// AppKit will reuse the window server resources efficiently on its own.
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Private

    private func updatePosition() {
        guard let panel else { return }

        // Try to position near the focused text field using Accessibility
        if let caretRect = getCaretRect() {
            // Show the pill on the display the caret is on — it may not be the
            // primary screen — and keep it inside that display's visible area.
            let screen = ScreenPlacement.screen(containing: caretRect.origin)
                ?? ScreenPlacement.current
            if let screen {
                panel.setFrameOrigin(
                    ScreenPlacement.place(size: panel.frame.size, above: caretRect, on: screen)
                )
                return
            }
        }

        // Fallback: center-bottom of the display the user is working on
        if let screen = ScreenPlacement.current {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - panel.frame.width / 2
            let y = screenFrame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Returns the caret / selection bounding rect in AppKit screen coordinates
    /// (bottom-left origin).  Returns `nil` if accessibility is unavailable or
    /// no focused element is found.
    private func getCaretRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else { return nil }

        let element = focusedElement as! AXUIElement

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRange
        ) == .success else { return nil }

        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &bounds
        ) == .success else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect) else { return nil }

        // AX coordinates are rooted at the top-left of the primary screen, not
        // at whichever screen the focused element happens to live on.
        return ScreenPlacement.appKitRect(fromAXRect: rect)
    }
}
