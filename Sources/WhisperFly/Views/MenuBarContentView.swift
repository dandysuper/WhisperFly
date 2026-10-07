import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openSettings) private var openSettings
    private let panelWidth: CGFloat = 320
    private let panelHeight: CGFloat = 520

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusHeader

                // Only the permissions that actually block what the user is
                // about to do are shown. Accessibility is listed whenever it is
                // missing because text insertion needs it for the microphone and
                // the status pill follows the caret through it.
                ForEach(permissionWarnings) { kind in
                    PermissionRow(
                        kind: kind,
                        state: controller.permissions.state(for: kind),
                        isCompact: true,
                        onRequest: { controller.requestPermission(kind) },
                        onOpenSettings: { controller.permissions.openSettings(for: kind) },
                        onRefresh: { Task { await controller.permissions.refresh(kind) } }
                    )
                }

                if case .updateAvailable(let commit) = controller.updates.status {
                    updateBanner(commit)
                }

                Divider()

                Picker("", selection: $controller.settings.audioSource) {
                    ForEach(AppSettings.AudioSource.allCases) { source in
                        Label(source.localizedName, systemImage: source.systemImage).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)
                .onChange(of: controller.settings.audioSource) { _, _ in controller.saveSettings() }

                recordButton
                transcribeFileButton
                historyButton

                if controller.status == .recording {
                    AudioLevelBar(level: controller.audioLevel)
                        .frame(height: 6)
                        .animation(.easeOut(duration: 0.05), value: controller.audioLevel)
                }

                backendInfo
                lastResult

                if case .error(let message) = controller.status {
                    errorRow(message)
                } else if let message = controller.errorMessage {
                    errorRow(message)
                }

                Divider()
                footer
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: panelWidth, height: panelHeight)
        .transaction { transaction in
            transaction.animation = nil
        }
        .onAppear {
            Task { await controller.permissions.refreshOnActivation() }
        }
    }

    // MARK: - Sections

    private var statusHeader: some View {
        HStack {
            Image(systemName: controller.status.iconName)
                .foregroundColor(statusColor)
            Text(controller.status.statusText)
                .font(.headline)
            Spacer()
            if !controller.hasValidAPIKeys {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.yellow)
                    .help(L("menu.api_keys_missing", "API keys not configured"))
            }
        }
    }

    private func updateBanner(_ commit: RemoteCommit) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 1) {
                Text(L("menu.update_available", "Update available"))
                    .font(.system(size: 11, weight: .medium))
                Text(commit.headline)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(L("menu.update_now", "Update")) {
                controller.installUpdate(using: controller.updates.preferredInstallMethod)
            }
            .font(.caption)
            .buttonStyle(.borderedProminent)
            .disabled(controller.updates.isBusy)
        }
        .padding(8)
        .background(Color.blue.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var recordButton: some View {
        Button(action: toggleRecording) {
            HStack {
                Image(systemName: controller.status == .recording
                      ? "stop.circle.fill"
                      : (controller.settings.audioSource == .systemAudio
                         ? "speaker.wave.2.circle.fill" : "mic.circle.fill"))
                    .font(.title2)
                Text(controller.status == .recording
                     ? L("menu.stop_recording", "Stop Recording")
                     : (controller.settings.audioSource == .systemAudio
                        ? L("menu.start_capture", "Capture System Audio")
                        : L("menu.start_recording", "Start Recording")))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(controller.status == .recording ? .red : .blue)
        .disabled(controller.status.isProcessing)
    }

    private var transcribeFileButton: some View {
        Button(action: { controller.transcribeFile() }) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                Text(L("menu.transcribe_file", "Transcribe File…"))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .disabled(!controller.hasValidAPIKeys || controller.status != .idle)
    }

    private var historyButton: some View {
        Button(action: { controller.showHistory() }) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                Text(L("menu.history", "History"))
                if !controller.history.entries.isEmpty {
                    Spacer()
                    Text("\(controller.history.entries.count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    private var backendInfo: some View {
        GroupBox(L("menu.transcription", "Transcription")) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("menu.backend", "Backend:"))
                        .foregroundColor(.secondary)
                    Text(controller.settings.transcriptionBackend.displayName)
                        .fontWeight(.medium)
                }
                .font(.caption)

                if controller.settings.geminiRewriteEnabled {
                    HStack {
                        Text(L("menu.rewrite", "Rewrite:"))
                            .foregroundColor(.secondary)
                        Text(controller.settings.rewriteMode.localizedName)
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }

                if controller.lastLatency > 0 {
                    HStack {
                        Text(L("menu.last_latency", "Last latency:"))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1fs", controller.lastLatency))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var lastResult: some View {
        if !controller.lastTranscription.isEmpty {
            GroupBox(L("menu.last_result", "Last Result")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("menu.raw", "Raw:"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(controller.lastTranscription)
                        .font(.caption)
                        .textSelection(.enabled)
                        .lineLimit(3)

                    if !controller.lastRewrite.isEmpty {
                        Text(L("menu.rewritten", "Rewritten:"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        Text(controller.lastRewrite)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(L("menu.dismiss", "Dismiss")) {
                controller.dismissError()
            }
            .font(.caption)
        }
    }

    private var footer: some View {
        HStack {
            Button(L("menu.settings", "Settings…")) {
                openSettings()
            }
            .font(.caption)

            Spacer()

            Button(L("menu.quit", "Quit")) {
                NSApplication.shared.terminate(nil)
            }
            .font(.caption)
        }
    }

    // MARK: - Helpers

    private func toggleRecording() {
        if controller.status == .idle {
            controller.startRecording()
        } else if controller.status == .recording {
            controller.finishRecording()
        }
    }

    /// The permissions whose absence stops the currently selected source from
    /// working, in the order the user would hit them.
    private var permissionWarnings: [PermissionKind] {
        var kinds: [PermissionKind] = []
        switch controller.settings.audioSource {
        case .microphone:
            if !controller.permissions.isGranted(.microphone) { kinds.append(.microphone) }
        case .systemAudio:
            if !controller.permissions.isGranted(.screenRecording) { kinds.append(.screenRecording) }
        }
        if !controller.permissions.isGranted(.accessibility) { kinds.append(.accessibility) }
        return kinds
    }

    private var statusColor: Color {
        switch controller.status {
        case .idle: return .green
        case .recording: return .red
        case .transcribing, .rewriting: return .orange
        case .pasting: return .blue
        case .error: return .red
        }
    }
}

struct AudioLevelBar: View {
    let level: Float // dBFS, typically -160 to 0

    private var normalizedLevel: CGFloat {
        let clamped = max(-60, min(0, level))
        return CGFloat((clamped + 60) / 60)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.gray.opacity(0.2))
                RoundedRectangle(cornerRadius: 3)
                    .fill(barColor)
                    .frame(width: geo.size.width * normalizedLevel)
            }
        }
    }

    private var barColor: Color {
        if normalizedLevel > 0.8 { return .red }
        if normalizedLevel > 0.5 { return .yellow }
        return .green
    }
}
