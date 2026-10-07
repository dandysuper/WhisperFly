import AppKit

/// Places floating panels on the display the user is actually working on.
///
/// Every helper here exists because a menu-bar app cannot rely on `NSScreen.main`
/// (the screen holding the key window — meaningless for an accessory app that
/// owns no key window) or on `NSWindow.center()` (always the primary screen).
/// The user's display is located through the mouse pointer instead, which is
/// where their attention is when a hotkey-triggered panel appears.
@MainActor
enum ScreenPlacement {

    /// The display the user is currently interacting with: the one under the
    /// pointer, falling back to `NSScreen.main` and then to any screen at all.
    static var current: NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let screen = screen(containing: mouse) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// The screen whose frame contains `point` in AppKit's global coordinates.
    static func screen(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    /// Converts a rect from the Accessibility global space to AppKit's space.
    ///
    /// AX reports bounds with their origin at the top-left of the **primary**
    /// screen (the one at index 0 of `NSScreen.screens`), regardless of which
    /// display the element lives on. The previous conversion used
    /// `NSScreen.main`'s height, so with any screen arranged above or beside the
    /// primary one the status pill landed on the wrong display or off-screen.
    static func appKitRect(fromAXRect rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? rect.maxY
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    /// Puts `window` at the centre of the user's current display.
    static func center(_ window: NSWindow) {
        guard let screen = current else {
            window.center()
            return
        }
        let visible = screen.visibleFrame
        let frame = window.frame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            y: visible.midY - frame.height / 2
        ))
    }

    /// Positions a panel of `size` near `anchorRect` (AppKit coordinates),
    /// staying inside `screen`'s visible area.
    ///
    /// Prefers floating above the anchor with a small gap, flips below it when
    /// that would cross the top of the display, and clamps horizontally so the
    /// panel never straddles a screen edge.
    static func place(size: NSSize, above anchorRect: CGRect, on screen: NSScreen) -> NSPoint {
        let visible = screen.visibleFrame
        let gap: CGFloat = 8
        let margin: CGFloat = 4

        var origin = NSPoint(x: anchorRect.minX + gap, y: anchorRect.maxY + gap)
        if origin.y + size.height > visible.maxY {
            origin.y = anchorRect.minY - gap - size.height
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        return origin
    }
}
