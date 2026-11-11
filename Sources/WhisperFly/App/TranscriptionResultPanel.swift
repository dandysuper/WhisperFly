import AppKit
import SwiftUI

/// A floating glass window showing one transcription in full.
@MainActor
final class TranscriptionResultPanel {
    private var panel: GlassPanel?

    func show(entry: TranscriptionEntry) {
        close()

        let size = NSSize(width: 460, height: 360)
        let p = GlassPanel(size: size)
        p.minSize = NSSize(width: 360, height: 240)
        p.onCancel = { [weak self] in self?.close() }

        let view = TranscriptionResultView(entry: entry, onClose: { [weak self] in self?.close() })
        let hosting = FirstMouseHostingView(rootView: view)
        p.contentView = GlassWindowContent.make(hosting: hosting, cornerRadius: 26)
        // `NSWindow.center()` targets the primary screen; the result belongs on
        // the display the user is working on.
        ScreenPlacement.center(p)

        self.panel = p
        p.orderFrontRegardless()
        p.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The floating glass history browser.
@MainActor
final class HistoryPanel {
    private var panel: GlassPanel?

    func toggle(controller: AppController, resultPanel: TranscriptionResultPanel) {
        if let panel, panel.isVisible {
            close()
            return
        }
        close()

        let size = NSSize(width: 460, height: 580)
        let p = GlassPanel(size: size)
        p.minSize = NSSize(width: 380, height: 360)
        p.onCancel = { [weak self] in self?.close() }

        let view = HistoryView(
            history: controller.history,
            onSelect: { entry in resultPanel.show(entry: entry) },
            onClose: { [weak self] in self?.close() }
        )
        let hosting = FirstMouseHostingView(rootView: view)
        p.contentView = GlassWindowContent.make(hosting: hosting, cornerRadius: 26)
        ScreenPlacement.center(p)

        self.panel = p
        p.orderFrontRegardless()
        p.makeKey()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
