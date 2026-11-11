import SwiftUI

/// Binds the floating pill to the live pipeline.
struct FloatingStatusView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var meter: AudioMeter

    var body: some View {
        FloatingPill(
            status: controller.status,
            isSystemAudio: (controller.activeAudioSource ?? controller.settings.audioSource) == .systemAudio,
            recordingStartedAt: controller.recordingStartedAt,
            detail: controller.activityDetail,
            failureAction: controller.lastFailure?.action,
            copiedFromMicrophone: controller.lastResult?.source == .microphone,
            levels: meter.levels,
            onCancel: { controller.cancelCurrentOperation() },
            onStop: { controller.finishRecording() },
            onAction: { controller.perform($0) }
        )
    }
}

/// The floating pill: live waveform while recording, progress while working,
/// a confirmation when done, and an actionable message when something failed.
///
/// Built from separate glass shapes (cancel, pill, stop) inside a `GlassGroup`,
/// so on macOS 26 they merge and split like liquid as the state changes. Pure
/// data in, callbacks out, so every state can be rendered on its own.
struct FloatingPill: View {
    let status: PipelineStatus
    let isSystemAudio: Bool
    let recordingStartedAt: Date?
    let detail: String
    let failureAction: DictationFailure.Action?
    let copiedFromMicrophone: Bool
    let levels: [CGFloat]
    let onCancel: () -> Void
    let onStop: () -> Void
    let onAction: (DictationFailure.Action) -> Void

    @Namespace private var glassSpace

    var body: some View {
        GlassGroup(spacing: 8) {
            HStack(spacing: 6) {
                if showsLeadingButton {
                    leadingButton
                        .glassID("leading", in: glassSpace)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }

                pill
                    .glassID("pill", in: glassSpace)

                if status == .recording {
                    stopButton
                        .glassID("stop", in: glassSpace)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: phase)
    }

    // MARK: - Pill

    private var pill: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .liquidGlass(Capsule(), tint: pillTint, interactive: false)
    }

    @ViewBuilder
    private var content: some View {
        switch status {
        case .recording:
            Circle()
                .fill(Color.red)
                .frame(width: 7, height: 7)
                .shadow(color: .red.opacity(0.7), radius: 4)
            LiveWaveform(levels: levels, tint: isSystemAudio ? .blue : .primary)
                .frame(width: 118, height: 24)
            if let start = recordingStartedAt {
                Text(start, style: .timer)
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 34, alignment: .trailing)
            }

        case .transcribing:
            ProgressView().controlSize(.small)
            label(L("floating.transcribing", "Transcribing…"), detail: detail)

        case .rewriting:
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .pulsingSymbol()
            label(L("floating.polishing", "Polishing…"), detail: detail)

        case .pasting:
            ProgressView().controlSize(.small)
            label(L("floating.inserting", "Inserting…"), detail: nil)

        case .done(let delivery):
            Image(systemName: delivery == .inserted ? "checkmark.circle.fill" : "doc.on.clipboard.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
                .bounceSymbol(on: phase)
            label(doneTitle(delivery), detail: doneDetail(delivery))

        case .error(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .frame(maxWidth: 270, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            if let action = failureAction {
                Button(actionTitle(action)) { onAction(action) }
                    .controlSize(.small)
                    .glassButton(prominent: true)
            }

        case .idle:
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .leading)
            }
        }
    }

    // MARK: - Side buttons

    private var showsLeadingButton: Bool {
        status.isBusy || status.isError
    }

    private var leadingButton: some View {
        Button(action: onCancel) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(Circle(), interactive: true)
        .help(status.isError
              ? L("floating.dismiss", "Dismiss")
              : L("floating.cancel_hint", "Cancel (Esc)"))
    }

    private var stopButton: some View {
        Button(action: onStop) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(.white)
                .frame(width: 12, height: 12)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .liquidGlass(Circle(), tint: .red, interactive: true)
        .help(L("floating.stop_hint", "Stop and transcribe"))
    }

    // MARK: - Helpers

    /// Changes only when the visual state does, so the spring is not re-run on
    /// every meter tick.
    private var phase: String {
        switch status {
        case .idle:          return "idle"
        case .recording:     return "recording"
        case .transcribing:  return "transcribing"
        case .rewriting:     return "rewriting"
        case .pasting:       return "pasting"
        case .done(let d):   return "done-\(d)"
        case .error(let m):  return "error-\(m)"
        }
    }

    private var pillTint: Color? {
        switch status {
        case .error: return .orange.opacity(0.35)
        case .done:  return .green.opacity(0.25)
        default:     return nil
        }
    }

    private func doneTitle(_ delivery: PipelineStatus.Delivery) -> String {
        delivery == .inserted ? L("floating.done", "Done") : L("floating.copied", "Copied")
    }

    private func doneDetail(_ delivery: PipelineStatus.Delivery) -> String? {
        guard delivery == .copied, copiedFromMicrophone else { return nil }
        return L("floating.copied_hint", "Press ⌘V to paste")
    }

    private func actionTitle(_ action: DictationFailure.Action) -> String {
        switch action {
        case .retry:          return L("action.retry", "Retry")
        case .openProviders:  return L("action.add_key", "Add Key")
        case .openPermission: return L("action.open_settings", "Open Settings")
        }
    }
}

/// Scrolling level bars, newest on the right, mirrored around the centre line.
struct LiveWaveform: View {
    let levels: [CGFloat]
    var tint: Color = .primary

    var body: some View {
        GeometryReader { geometry in
            let count = max(levels.count, 1)
            let spacing: CGFloat = 2
            let width = max(1.5, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    Capsule()
                        .fill(tint.opacity(0.35 + 0.65 * Double(index) / Double(count)))
                        .frame(width: width, height: max(3, level * geometry.size.height))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .animation(.easeOut(duration: 0.08), value: levels)
        }
    }
}
