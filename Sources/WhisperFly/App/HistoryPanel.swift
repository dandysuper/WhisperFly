import AppKit
import SwiftUI

@MainActor
final class HistoryPanel {
    private var panel: NSPanel?

    func show(history: TranscriptionHistory, resultPanel: TranscriptionResultPanel) {
        if panel != nil { close(); return }

        let view = HistoryView(
            history: history,
            onSelect: { [weak self] entry in
                self?.close()
                resultPanel.show(
                    text: entry.text,
                    source: entry.source == .microphone ? .microphone
                          : entry.source == .systemAudio ? .systemAudio : .file,
                    fileName: entry.fileName
                )
            },
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 360, height: 400)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 400),
            styleMask: [.titled, .closable, .nonactivatingPanel, .hudWindow],
            backing: .buffered,
            defer: false
        )
        p.title = "WhisperFly — History"
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
