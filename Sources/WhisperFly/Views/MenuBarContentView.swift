import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status Header
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
            
            // Accessibility warning
            if !controller.accessibilityGranted {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("menu.accessibility_required", "Accessibility permission required"))
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(L("menu.accessibility_hint", "Needed to type text into apps"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(L("menu.grant", "Grant")) {
                        controller.checkAccessibilityPermission()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Screen Recording warning (only when system audio is selected)
            if controller.settings.audioSource == .systemAudio && !controller.screenRecordingGranted {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.dashed.badge.record")
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("menu.screen_recording_required", "Screen Recording permission required"))
                            .font(.caption)
                            .fontWeight(.medium)
                        Text(L("menu.screen_recording_hint", "Needed to capture system audio"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(L("menu.grant", "Grant")) {
                        controller.requestScreenRecordingPermission()
                    }
                    .font(.caption)
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                }
                .padding(8)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(6)
            }
            
            Divider()
            
            // Audio Source Picker
            Picker("", selection: $controller.settings.audioSource) {
                ForEach(AppSettings.AudioSource.allCases, id: \.self) { source in
                    Label(source.localizedName, systemImage: source == .microphone ? "mic.fill" : "speaker.wave.2.fill")
                        .tag(source)
                }
            }
            .pickerStyle(.segmented)
            .padding(.bottom, 4)
            
            // Record Button
            Button(action: {
                if controller.status == .idle {
                    controller.startRecording()
                } else if controller.status == .recording {
                    controller.finishRecording()
                }
            }) {
                HStack {
                    Image(systemName: controller.status == .recording
                          ? "stop.circle.fill"
                          : (controller.settings.audioSource == .systemAudio ? "speaker.wave.2.circle.fill" : "mic.circle.fill"))
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
            
            // Transcribe File Button
            Button(action: {
                controller.transcribeFile()
            }) {
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
            
            // History Button
            Button(action: {
                controller.showHistory()
            }) {
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
            
            // Audio Level Meter
            if controller.status == .recording {
                AudioLevelBar(level: controller.audioLevel)
                    .frame(height: 6)
                    .animation(.easeOut(duration: 0.05), value: controller.audioLevel)
            }
            
            // Backend Info
            GroupBox(L("menu.transcription", "Transcription")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(L("menu.backend", "Backend:"))
                            .foregroundColor(.secondary)
                        Text(controller.settings.transcriptionBackend.rawValue)
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
            
            // Last Transcription
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
            
            // Error
            if case .error(let msg) = controller.status {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(2)
                    Spacer()
                    Button(L("menu.dismiss", "Dismiss")) {
                        controller.dismissError()
                    }
                    .font(.caption)
                }
            }
            
            Divider()
            
            // Bottom actions
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
        .padding(12)
        .frame(width: 320)
        .onAppear {
            controller.refreshAccessibility()
            controller.checkScreenRecordingPermission()
        }
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
