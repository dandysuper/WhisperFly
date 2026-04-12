import AppKit
import SwiftUI

@MainActor
final class TranscriptionResultPanel {
    private var panel: NSPanel?

    func show(text: String, source: TranscriptionEntry.Source, fileName: String? = nil) {
        close()

        let view = TranscriptionResultView(
            text: text,
            source: source,
            fileName: fileName,
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 280)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "WhisperFly"
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = hosting
        p.isReleasedWhenClosed = false
        p.center()

        self.panel = p
        p.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
