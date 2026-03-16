import SwiftUI

@main
struct WhisperFlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var controller = AppController()
    
    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(controller: controller)
        } label: {
            Image(systemName: controller.status.iconName)
        }
        .menuBarExtraStyle(.window)
        
        Settings {
            SettingsView(controller: controller)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
