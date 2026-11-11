import AppKit
import SwiftUI

/// The floating Liquid Glass pill that shows recording, progress and results.
///
/// The panel is a fixed-size transparent canvas and the pill is centred in it,
/// so the pill can grow and morph between states without the window resizing
/// mid-animation. Clicks on the transparent margin fall through to the app below.
@MainActor
final class FloatingPanel {
    private var panel: NSPanel?
    private static let canvasSize = NSSize(width: 520, height: 84)

    func show(with controller: AppController) {
        if let existing = panel {
            // Reuse the existing panel — just reposition and bring to front.
            // Never recreate: releasing NSPanel while a layout pass is still in
            // flight triggers EXC_BREAKPOINT (_postWindowNeedsUpdateConstraints)
            // on macOS 26 (Tahoe).
            if !existing.isVisible { updatePosition() }
            existing.orderFrontRegardless()
            return
        }

        let hosting = FirstMouseHostingView(rootView: FloatingStatusView(controller: controller, meter: controller.meter))
        hosting.frame = NSRect(origin: .zero, size: Self.canvasSize)

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        // Glass draws its own shadow; a window shadow would outline the canvas.
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = false
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.contentView = hosting

        self.panel = p
        updatePosition()
        p.orderFrontRegardless()
    }

    /// Hides the panel without releasing it.
    ///
    /// We intentionally keep `panel` alive indefinitely. Releasing an NSPanel
    /// while AppKit still has a deferred layout pass pending causes an
    /// EXC_BREAKPOINT crash inside `_postWindowNeedsUpdateConstraints` on
    /// macOS 26. `orderOut` is sufficient to remove the panel from the screen.
    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Placement

    private func updatePosition() {
        guard let panel else { return }
        let size = panel.frame.size

        // Near the caret when the focused app exposes it, on that caret's display.
        if let caret = caretRect(),
           let screen = ScreenPlacement.screen(containing: caret.origin) ?? ScreenPlacement.current {
            let visible = screen.visibleFrame
            var origin = NSPoint(x: caret.minX - size.width / 2 + 60, y: caret.maxY + 4)
            if origin.y + size.height > visible.maxY {
                origin.y = caret.minY - size.height - 4
            }
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
            panel.setFrameOrigin(origin)
            return
        }

        // Otherwise bottom-centre of the display the user is working on.
        if let screen = ScreenPlacement.current {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 48))
        }
    }

    /// The caret / selection rect in AppKit screen coordinates, or `nil` when
    /// Accessibility is unavailable or nothing focused exposes one.
    private func caretRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success,
              let selectedRange else { return nil }

        var bounds: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRange, &bounds
        ) == .success, let bounds, CFGetTypeID(bounds) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(bounds as! AXValue, .cgRect, &rect), rect.width < 2000, rect.height < 400 else { return nil }
        // AX coordinates are rooted at the top-left of the primary screen.
        return ScreenPlacement.appKitRect(fromAXRect: rect)
    }
}
