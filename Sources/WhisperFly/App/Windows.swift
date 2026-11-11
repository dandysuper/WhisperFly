import AppKit
import SwiftUI

/// Settings sections, in sidebar order.
enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general
    case providers
    case rewriting
    case permissions
    case updates
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:     return L("settings.tab.general", "General")
        case .providers:   return L("settings.tab.providers", "Speech Engines")
        case .rewriting:   return L("settings.tab.rewriting", "AI Rewriting")
        case .permissions: return L("settings.tab.permissions", "Permissions")
        case .updates:     return L("settings.tab.updates", "Updates")
        case .advanced:    return L("settings.tab.advanced", "Advanced")
        }
    }

    var systemImage: String {
        switch self {
        case .general:     return "gearshape"
        case .providers:   return "waveform.badge.mic"
        case .rewriting:   return "wand.and.stars"
        case .permissions: return "lock.shield"
        case .updates:     return "arrow.down.circle"
        case .advanced:    return "slider.horizontal.3"
        }
    }

    var tint: Color {
        switch self {
        case .general:     return .gray
        case .providers:   return .orange
        case .rewriting:   return .purple
        case .permissions: return .green
        case .updates:     return .blue
        case .advanced:    return .indigo
        }
    }
}

/// Which settings section is showing; lets other parts of the app deep-link.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsSection? = .general
}

/// A regular titled window hosting SwiftUI, managed by AppKit.
///
/// SwiftUI's `Settings` scene cannot be opened reliably from a menu-bar
/// (`LSUIElement`) app on recent macOS, cannot be deep-linked to a section, and
/// opens behind the frontmost app. Owning the window fixes all three.
@MainActor
class HostedWindowController<Content: View> {
    private var window: NSWindow?
    private let makeContent: () -> Content
    private let title: String
    private let size: NSSize
    private let minSize: NSSize
    private let autosaveName: String

    init(title: String, size: NSSize, minSize: NSSize, autosaveName: String, content: @escaping () -> Content) {
        self.title = title
        self.size = size
        self.minSize = minSize
        self.autosaveName = autosaveName
        self.makeContent = content
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: makeContent())
            hosting.sizingOptions = []
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentViewController = hosting
            window.title = title
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.minSize = minSize
            window.setContentSize(size)
            window.collectionBehavior = [.fullScreenNone, .moveToActiveSpace]
            if !window.setFrameUsingName(autosaveName) {
                ScreenPlacement.center(window)
            }
            window.setFrameAutosaveName(autosaveName)
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    var isVisible: Bool { window?.isVisible ?? false }
}

@MainActor
final class SettingsWindowController: HostedWindowController<SettingsView> {
    init(controller: AppController) {
        super.init(
            title: L("settings.window_title", "WhisperFly Settings"),
            size: NSSize(width: 780, height: 560),
            minSize: NSSize(width: 680, height: 460),
            autosaveName: "WhisperFlySettingsWindow"
        ) {
            SettingsView(controller: controller, navigation: controller.navigation)
        }
    }
}

@MainActor
final class OnboardingWindowController: HostedWindowController<OnboardingView> {
    init(controller: AppController) {
        super.init(
            title: L("onboarding.window_title", "Welcome to WhisperFly"),
            size: NSSize(width: 600, height: 620),
            minSize: NSSize(width: 560, height: 560),
            autosaveName: "WhisperFlyOnboardingWindow"
        ) {
            OnboardingView(controller: controller, permissions: controller.permissions)
        }
    }
}
