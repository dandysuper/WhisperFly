import SwiftUI

struct TranscriptionResultView: View {
    let text: String
    let source: TranscriptionEntry.Source
    let fileName: String?
    let onClose: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: sourceIcon)
                    .foregroundColor(.accentColor)
                Text(headerLabel)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Transcribed text
            ScrollView {
                Text(text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 200)

            Divider()

            // Actions
            HStack {
                Button(action: copyToClipboard) {
                    Label(copied
                          ? L("result.copied", "Copied ✓")
                          : L("result.copy", "Copy"),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                .tint(copied ? .green : .accentColor)

                Spacer()

                Text("\(text.count) " + L("result.chars", "chars"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 380, height: 280)
        .onAppear {
            copyToClipboard()
        }
    }

    private var sourceIcon: String {
        switch source {
        case .microphone:  return "mic.fill"
        case .systemAudio: return "speaker.wave.2.fill"
        case .file:        return "doc.text.fill"
        }
    }

    private var headerLabel: String {
        switch source {
        case .microphone:  return L("result.title.mic", "Transcription")
        case .systemAudio: return L("result.title.system", "System Audio Transcription")
        case .file:
            if let name = fileName {
                return name
            }
            return L("result.title.file", "File Transcription")
        }
    }

    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}
