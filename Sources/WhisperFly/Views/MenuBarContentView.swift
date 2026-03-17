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
                        .help(Text("menu.api_keys_missing"))
                }
            }
            
            Divider()
            
            // Record Button
            Button(action: {
                if controller.status == .idle {
                    controller.startRecording()
                } else if controller.status == .recording {
                    controller.finishRecording()
                }
            }) {
                HStack {
                    Image(systemName: controller.status == .recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title2)
                    Text(controller.status == .recording ? "menu.stop_recording" : "menu.start_recording")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(controller.status == .recording ? .red : .blue)
            .disabled(controller.status.isProcessing)
            
            // Audio Level Meter
            if controller.status == .recording {
                AudioLevelBar(level: controller.audioLevel)
                    .frame(height: 6)
                    .animation(.easeOut(duration: 0.05), value: controller.audioLevel)
            }
            
            // Backend Info
            GroupBox(String(localized: "menu.transcription", defaultValue: "Transcription")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("menu.backend")
                            .foregroundColor(.secondary)
                        Text(controller.settings.transcriptionBackend.rawValue)
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                    
                    if controller.settings.geminiRewriteEnabled {
                        HStack {
                            Text("menu.rewrite")
                                .foregroundColor(.secondary)
                            Text(controller.settings.rewriteMode.localizedName)
                                .fontWeight(.medium)
                        }
                        .font(.caption)
                    }
                    
                    if controller.lastLatency > 0 {
                        HStack {
                            Text("menu.last_latency")
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
                GroupBox(String(localized: "menu.last_result", defaultValue: "Last Result")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("menu.raw")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(controller.lastTranscription)
                            .font(.caption)
                            .textSelection(.enabled)
                            .lineLimit(3)
                        
                        if !controller.lastRewrite.isEmpty {
                            Text("menu.rewritten")
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
                    Button("menu.dismiss") {
                        controller.dismissError()
                    }
                    .font(.caption)
                }
            }
            
            Divider()
            
            // Bottom actions
            HStack {
                Button("menu.settings") {
                    openSettings()
                }
                .font(.caption)
                
                Spacer()
                
                Button("menu.quit") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(width: 320)
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
