import SwiftUI

struct HistoryView: View {
    @ObservedObject var history: TranscriptionHistory
    let onSelect: (TranscriptionEntry) -> Void
    let onClose: () -> Void

    @StateObject private var query = LocalState("")
    @StateObject private var confirmClear = LocalFlag(false)

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            if history.entries.isEmpty {
                emptyState(
                    icon: "waveform.badge.mic",
                    title: L("history.empty", "No transcriptions yet"),
                    message: L("history.empty_hint", "Your dictations and file transcriptions will appear here.")
                )
            } else if filtered.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: L("history.no_matches", "No matches"),
                    message: L("history.no_matches_hint", "Try a different search.")
                )
            } else {
                list
            }
        }
        .frame(minWidth: 380, minHeight: 360)
        .confirmationDialog(
            L("history.clear_confirm", "Delete all transcriptions?"),
            isPresented: $confirmClear.value
        ) {
            Button(L("history.clear", "Clear All"), role: .destructive) { history.clear() }
        } message: {
            Text(L("history.clear_message", "This cannot be undone."))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text(L("history.title", "History"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                if !history.entries.isEmpty {
                    Chip(text: "\(history.entries.count)")
                }
                Spacer()
                if !history.entries.isEmpty {
                    Button {
                        confirmClear.value = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .liquidGlass(Circle(), interactive: true)
                    .help(L("history.clear", "Clear All"))
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .liquidGlass(Circle(), interactive: true)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("history.search", "Search"), text: $query.value)
                    .textFieldStyle(.plain)
                if !query.value.isEmpty {
                    Button { query.value = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }

    // MARK: - List

    private var filtered: [TranscriptionEntry] {
        let needle = query.value.trimmed
        guard !needle.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(needle)
                || ($0.fileName?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    private var sections: [(title: String, entries: [TranscriptionEntry])] {
        let calendar = Calendar.current
        var result: [(String, [TranscriptionEntry])] = []
        for entry in filtered {
            let title: String
            if calendar.isDateInToday(entry.date) {
                title = L("history.today", "Today")
            } else if calendar.isDateInYesterday(entry.date) {
                title = L("history.yesterday", "Yesterday")
            } else {
                title = entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
            }
            if let last = result.last, last.0 == title {
                result[result.count - 1].1.append(entry)
            } else {
                result.append((title, [entry]))
            }
        }
        return result
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6, pinnedViews: []) {
                ForEach(sections, id: \.title) { section in
                    Text(section.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 10)
                        .padding(.leading, 6)

                    ForEach(section.entries) { entry in
                        HistoryRow(
                            entry: entry,
                            onOpen: { onSelect(entry) },
                            onDelete: { withAnimation { history.remove(id: entry.id) } }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity)
    }
}

struct HistoryRow: View {
    let entry: TranscriptionEntry
    let onOpen: () -> Void
    let onDelete: () -> Void

    @StateObject private var copied = LocalFlag(false)
    @StateObject private var hovering = LocalFlag(false)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.sourceIcon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.06)))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(.system(size: 12.5))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 5) {
                    Text(entry.date.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text(entry.sourceLabel).lineLimit(1)
                    Text("·")
                    Text(L("history.words", "%d words", entry.wordCount))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }

            VStack(spacing: 4) {
                Button(action: copy) {
                    Image(systemName: copied.value ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(copied.value ? .green : .secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("history.copy_tooltip", "Copy to clipboard"))

                if hovering.value {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("history.delete", "Delete"))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(hovering.value ? 0.08 : 0.04))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onOpen)
        .onHover { hovering.value = $0 }
        .contextMenu {
            Button(L("history.copy_tooltip", "Copy to clipboard"), action: copy)
            Button(L("history.open", "Open"), action: onOpen)
            Divider()
            Button(L("history.delete", "Delete"), role: .destructive, action: onDelete)
        }
    }

    private func copy() {
        ClipboardWriter.write(entry.text)
        withAnimation { copied.value = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { copied.value = false }
        }
    }
}
