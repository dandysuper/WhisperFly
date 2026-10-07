import AppKit

/// Single place that writes to `NSPasteboard.general`.
///
/// Every copy/paste site in the app used to inline `clearContents()` +
/// `setString(_:forType:)`. Centralising it keeps the pasteboard handling
/// consistent and makes clipboard snapshot/restore — used by the paste pipeline
/// so the user's original clipboard comes back after a dictation — testable.
enum ClipboardWriter {

    /// Replaces the clipboard contents with `text`, returning `false` if the
    /// pasteboard refused the write.
    @discardableResult
    static func write(_ text: String, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    /// A snapshot of every pasteboard item, preserving all declared types so rich
    /// content (images, RTF, file promises) survives a round-trip.
    struct Snapshot {
        let items: [[NSPasteboard.PasteboardType: Data]]

        var isEmpty: Bool { items.isEmpty }
    }

    static func snapshot(of pasteboard: NSPasteboard = .general) -> Snapshot {
        let items = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var snapshot: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot[type] = data
                }
            }
            return snapshot.isEmpty ? nil : snapshot
        } ?? []
        return Snapshot(items: items)
    }

    static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard = .general) {
        guard !snapshot.isEmpty else { return }
        pasteboard.clearContents()
        for entry in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in entry {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }
}
