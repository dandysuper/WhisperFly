import SwiftUI

struct FloatingStatusView: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        HStack(spacing: 8) {
            statusIcon
            statusLabel
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(borderColor.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch controller.status {
        case .recording:
            WaveformView(level: controller.audioLevel)
                .frame(width: 28, height: 18)
        case .transcribing, .rewriting:
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        case .pasting:
            Image(systemName: "doc.on.clipboard.fill")
                .foregroundColor(.blue)
                .font(.system(size: 14))
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var statusLabel: some View {
        switch controller.status {
        case .recording:
            Text("Listening…")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.red)
        case .transcribing:
            Text("Transcribing…")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.orange)
        case .rewriting:
            Text("Rewriting…")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.purple)
        case .pasting:
            Text("Done ✓")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.green)
        default:
            EmptyView()
        }
    }
    
    private var borderColor: Color {
        switch controller.status {
        case .recording: return .red
        case .transcribing: return .orange
        case .rewriting: return .purple
        case .pasting: return .green
        default: return .clear
        }
    }
}

struct WaveformView: View {
    let level: Float
    
    private var normalizedLevel: CGFloat {
        let clamped = max(-50, min(0, level))
        return CGFloat((clamped + 50) / 50)
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                WaveformBar(
                    height: barHeight(for: i),
                    color: .red
                )
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let base = normalizedLevel
        let offsets: [CGFloat] = [0.5, 0.8, 1.0, 0.7, 0.4]
        return max(0.15, base * offsets[index])
    }
}

struct WaveformBar: View {
    let height: CGFloat // 0...1
    let color: Color
    
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: 3, height: max(3, height * 18))
            .animation(.easeOut(duration: 0.08), value: height)
    }
}
