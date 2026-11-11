import SwiftUI
import AppKit

// Liquid Glass with a graceful fallback.
//
// macOS 26 introduced Liquid Glass (`glassEffect`, `GlassEffectContainer`, the
// `.glass` button styles and `NSGlassEffectView`). WhisperFly supports macOS 13,
// so every use goes through these helpers: on 26+ they produce real glass, on
// earlier systems — or when the user picks the classic look — translucent
// materials with the same shapes and layout.
//
// This file is the only one that names a glass API. The `compiler(>=6.2)` guard
// keeps it building with Xcode 16 and the macOS 15 SDK, which do not have them,
// so the app can still be built from source on an Intel Mac running Sonoma or
// Sequoia. `WHISPERFLY_NO_LIQUID_GLASS` forces that path for testing.

#if compiler(>=6.2) && !WHISPERFLY_NO_LIQUID_GLASS
private let sdkHasLiquidGlass = true
#else
private let sdkHasLiquidGlass = false
#endif

/// Decides between Liquid Glass and the classic materials.
@MainActor
enum LiquidGlassSupport {
    /// Set from `AppSettings.classicMaterials`; applies to views rendered and
    /// windows opened from then on.
    static var prefersClassic = false

    static var isActive: Bool {
        guard sdkHasLiquidGlass, !prefersClassic else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// `true` when this Mac could show Liquid Glass at all, so the setting is
    /// worth offering.
    static var isAvailable: Bool {
        guard sdkHasLiquidGlass else { return false }
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

extension View {

    /// Puts a Liquid Glass surface behind the view in `shape`.
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        #if compiler(>=6.2) && !WHISPERFLY_NO_LIQUID_GLASS
        if #available(macOS 26.0, *), LiquidGlassSupport.isActive {
            self.glassEffect(Self.glass(tint: tint, interactive: interactive), in: shape)
        } else {
            self.classicGlass(shape, tint: tint)
        }
        #else
        self.classicGlass(shape, tint: tint)
        #endif
    }

    /// The pre-macOS 26 stand-in: a material with a hairline and a soft shadow.
    /// Materials turn opaque by themselves when Reduce Transparency is on.
    private func classicGlass<S: Shape>(_ shape: S, tint: Color?) -> some View {
        self.background {
            ZStack {
                shape.fill(.regularMaterial)
                if let tint { shape.fill(tint.opacity(0.16)) }
                shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
            }
            .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
        }
    }

    /// Glass button style on macOS 26, bordered style before.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        #if compiler(>=6.2) && !WHISPERFLY_NO_LIQUID_GLASS
        if #available(macOS 26.0, *), LiquidGlassSupport.isActive {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            self.classicButton(prominent: prominent)
        }
        #else
        self.classicButton(prominent: prominent)
        #endif
    }

    @ViewBuilder
    private func classicButton(prominent: Bool) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    /// Ties the view to a morphing glass identity inside a `GlassGroup`.
    @ViewBuilder
    func glassID<ID: Hashable & Sendable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        #if compiler(>=6.2) && !WHISPERFLY_NO_LIQUID_GLASS
        if #available(macOS 26.0, *), LiquidGlassSupport.isActive {
            self.glassEffectID(id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    #if compiler(>=6.2) && !WHISPERFLY_NO_LIQUID_GLASS
    @available(macOS 26.0, *)
    private static func glass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }
    #endif
}

/// Lets nearby glass shapes blend and morph into each other on macOS 26.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: Content

    var body: some View {
        #if compiler(>=6.2) && !WHISPERFLY_NO_LIQUID_GLASS
        if #available(macOS 26.0, *), LiquidGlassSupport.isActive {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// A content card for use *inside* a glass window. Glass on glass muddies both
/// layers, so cards use a quiet fill and a hairline instead.
struct SurfaceCard<Content: View>: View {
    var padding: CGFloat = 12
    var cornerRadius: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
    }
}

/// A small capsule label, e.g. "Free" or a status.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 8, weight: .bold))
            }
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(Capsule().fill(tint.opacity(0.14)))
    }
}

/// A rendered keyboard shortcut: ⌘ ⇧ Space as individual key caps.
struct KeyCaps: View {
    let keys: [String]
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key)
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .padding(.horizontal, key.count > 1 ? 6 : 4)
                    .frame(minWidth: size + 9, minHeight: size + 9)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
            }
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - AppKit side

/// Builds the root view of a glass window: `NSGlassEffectView` on macOS 26,
/// a behind-window `NSVisualEffectView` before.
@MainActor
enum GlassWindowContent {

    static func make(hosting: NSView, cornerRadius: CGFloat) -> NSView {
        #if compiler(>=6.2) && !WHISPERFLY_NO_LIQUID_GLASS
        if #available(macOS 26.0, *), LiquidGlassSupport.isActive {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = hosting
            return glass
        }
        #endif

        // `.popover` follows light and dark mode; `.hudWindow` is dark-styled and
        // would put dark text on a dark panel in light mode.
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = roundedMask(radius: cornerRadius)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    /// A stretchable rounded-rect mask; `capInsets` keep the corners fixed.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A borderless panel that floats above other apps without activating
/// WhisperFly, yet can become key so text selection and ⌘C work.
final class GlassPanel: NSPanel {
    var onCancel: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Escape closes the panel.
    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { orderOut(nil) }
    }
}

/// Hosting view that reacts to the first click even when its window is not key,
/// so buttons on a floating panel work without first focusing it.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Warns that macOS also acts on the Fn key, with a shortcut to the setting.
struct FnConflictNotice: View {
    let conflict: SystemFnKeyAction
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.conflictDescription)
                    .font(.system(size: 11, weight: .medium))
                Text(L("fn.conflict.fix", "Set “Press 🌐 key to” to “Do Nothing” in Keyboard settings."))
                    .font(.system(size: compact ? 10 : 11))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(L("fn.conflict.open", "Open Keyboard")) {
                NSWorkspace.shared.open(SystemFnKeyAction.keyboardSettingsURL)
            }
            .controlSize(.small)
            .glassButton(prominent: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.10)))
    }
}
