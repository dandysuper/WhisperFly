import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: TranscriptionHistory
    let onSelect: (TranscriptionEntry) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.accentColor)
                Text(L("history.title", "History"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !history.entries.isEmpty {
                    Button(L("history.clear", "Clear All")) {
                        history.clear()
                    }
                    .font(.caption)
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if history.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .frame(width: 360, height: 400)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "text.bubble")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.5))
            Text(L("history.empty", "No transcriptions yet"))
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var entryList: some View {
        List {
            ForEach(history.entries) { entry in
                HistoryRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(entry) }
            }
            .onDelete { offsets in
                history.remove(at: offsets)
            }
        }
        .listStyle(.plain)
    }
}

struct HistoryRow: View {
    let entry: TranscriptionEntry
    @State private var copied = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: entry.sourceIcon)
                .foregroundColor(.secondary)
                .font(.system(size: 11))
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.tail)

                HStack(spacing: 6) {
                    Text(entry.sourceLabel)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(entry.date, style: .relative)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(action: { copyText() }) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(L("history.copy_tooltip", "Copy to clipboard"))
        }
        .padding(.vertical, 3)
    }

    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}
