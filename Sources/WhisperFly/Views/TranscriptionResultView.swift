import SwiftUI
import UniformTypeIdentifiers

struct TranscriptionResultView: View {
    let entry: TranscriptionEntry
    let onClose: () -> Void

    @StateObject private var copied = LocalFlag(false)
    @StateObject private var showOriginal = LocalFlag(false)

    private var displayedText: String {
        showOriginal.value ? (entry.rawText ?? entry.text) : entry.text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if entry.rawText != nil {
                Picker("", selection: $showOriginal.value) {
                    Text(L("result.polished", "Polished")).tag(false)
                    Text(L("result.original", "Original")).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            ScrollView {
                Text(displayedText)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )

            footer
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 240)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.sourceIcon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(sourceTint.gradient))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .liquidGlass(Circle(), interactive: true)
            .keyboardShortcut(.cancelAction)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(L("result.counts", "%d words · %d characters", wordCount, displayedText.count))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                save()
            } label: {
                Label(L("result.save", "Save…"), systemImage: "square.and.arrow.down")
            }
            .glassButton()

            Button {
                copy()
            } label: {
                Label(copied.value ? L("result.copied", "Copied") : L("result.copy", "Copy"),
                      systemImage: copied.value ? "checkmark" : "doc.on.doc")
                    .symbolReplaceTransition()
            }
            .glassButton(prominent: true)
            .tint(copied.value ? .green : .accentColor)
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
    }

    // MARK: - Derived

    private var title: String {
        switch entry.source {
        case .microphone:  return L("result.title.mic", "Dictation")
        case .systemAudio: return L("result.title.system", "System Audio")
        case .file:        return entry.fileName ?? L("result.title.file", "File Transcription")
        }
    }

    private var subtitle: String {
        var parts = [entry.date.formatted(date: .abbreviated, time: .shortened)]
        if let duration = entry.duration, duration > 0 {
            parts.append(Duration.seconds(duration).formatted(.time(pattern: duration >= 3600 ? .hourMinuteSecond : .minuteSecond)))
        }
        if let provider = entry.provider { parts.append(provider) }
        return parts.joined(separator: " · ")
    }

    private var wordCount: Int {
        displayedText.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var sourceTint: Color {
        switch entry.source {
        case .microphone:  return .red
        case .systemAudio: return .blue
        case .file:        return .indigo
        }
    }

    // MARK: - Actions

    private func copy() {
        ClipboardWriter.write(displayedText)
        withAnimation { copied.value = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation { copied.value = false }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let base = (entry.fileName as NSString?)?.deletingPathExtension ?? "Transcription"
        panel.nameFieldStringValue = "\(base).txt"
        NSApp.activateCompat()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? displayedText.write(to: url, atomically: true, encoding: .utf8)
    }
}
