import SwiftUI
import UniformTypeIdentifiers

/// The menu bar window: one big dictation button, the current engine and
/// rewrite mode, anything that needs attention, and recent results.
struct MenuBarContentView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var permissions: PermissionService
    @ObservedObject var updates: UpdateService
    @ObservedObject private var history: TranscriptionHistory
    @StateObject private var dropTargeted = LocalFlag(false)

    private let width: CGFloat = 344

    init(controller: AppController, permissions: PermissionService, updates: UpdateService) {
        self.controller = controller
        self.permissions = permissions
        self.updates = updates
        self.history = controller.history
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            recordSection
            attention
            engineSection
            if let result = controller.lastResult {
                lastResultCard(result)
            }
            recentSection
            footer
        }
        .padding(16)
        .frame(width: width)
        .overlay {
            if dropTargeted.value { dropOverlay }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            controller.transcribe(fileURL: url)
            return true
        } isTargeted: { dropTargeted.value = $0 }
        .onAppear {
            Task { await permissions.refreshOnActivation() }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text("WhisperFly")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                closeMenu()
                controller.openSettings()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .liquidGlass(Circle(), interactive: true)
            .help(L("menu.settings", "Settings…"))
        }
    }

    // MARK: - Record

    private var recordSection: some View {
        VStack(spacing: 10) {
            Button(action: recordTapped) {
                HStack(spacing: 10) {
                    Image(systemName: recordIcon)
                        .font(.system(size: 17, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text(recordTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 4)
                    if controller.status == .recording, let start = controller.recordingStartedAt {
                        Text(start, style: .timer)
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    } else {
                        KeyCaps(keys: controller.settings.hotkey.keyCaps, size: 10)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .controlSize(.large)
            .glassButton(prominent: true)
            .tint(controller.status == .recording ? .red : .accentColor)
            .disabled(controller.status.isProcessing)

            Picker("", selection: $controller.settings.audioSource) {
                ForEach(AppSettings.AudioSource.allCases) { source in
                    Label(source.localizedName, systemImage: source.systemImage).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(controller.status.isBusy)

            Text(hint)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Attention

    @ViewBuilder
    private var attention: some View {
        if !controller.isTranscriptionConfigured {
            setupCard
        }

        ForEach(permissionWarnings) { kind in
            PermissionRow(
                kind: kind,
                state: permissions.state(for: kind),
                isCompact: true,
                onRequest: { controller.requestPermission(kind) },
                onOpenSettings: { permissions.openSettings(for: kind) },
                onRefresh: { Task { await permissions.refresh(kind) } }
            )
        }

        if let conflict = controller.fnKeyConflict {
            FnConflictNotice(conflict: conflict, compact: true)
        }

        if let error = controller.hotkeyError {
            noticeRow(icon: "keyboard.badge.exclamationmark", tint: .orange, text: error) {
                Button(L("menu.change", "Change")) { closeMenu(); controller.openSettings(.general) }
            }
        }

        if let failure = controller.lastFailure, !controller.status.isBusy {
            noticeRow(icon: "exclamationmark.triangle.fill", tint: .orange, text: failure.message) {
                HStack(spacing: 4) {
                    if let action = failure.action {
                        Button(actionTitle(action)) { controller.perform(action) }
                            .glassButton(prominent: true)
                    }
                    Button {
                        controller.dismissFailure()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        if case .updateAvailable(let commit) = updates.status {
            noticeRow(icon: "arrow.down.circle.fill", tint: .blue, text: L("menu.update_available", "Update available") + " — " + commit.headline) {
                Button(L("menu.update_now", "Update")) {
                    controller.installUpdate(using: updates.preferredInstallMethod)
                }
                .glassButton(prominent: true)
                .disabled(updates.isBusy)
            }
        }
    }

    private var setupCard: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").foregroundStyle(.orange)
                    Text(L("menu.setup.title", "Add a free API key"))
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(L("menu.setup.body", "WhisperFly needs a speech engine. Groq and Google Gemini both have free tiers — a key takes a minute to create."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(L("menu.setup.button", "Set Up")) {
                        closeMenu()
                        controller.showOnboarding()
                    }
                    .glassButton(prominent: true)
                    Button(L("menu.setup.get_groq", "Get Groq Key")) {
                        if let url = AIProvider.groq.keyURL { NSWorkspace.shared.open(url) }
                    }
                    .glassButton()
                }
                .controlSize(.small)
            }
        }
    }

    private func noticeRow<Accessory: View>(icon: String, tint: Color, text: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            accessory()
                .controlSize(.small)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint.opacity(0.10)))
    }

    // MARK: - Engine

    private var engineSection: some View {
        SurfaceCard(padding: 4) {
            VStack(spacing: 0) {
                Button {
                    closeMenu()
                    controller.openSettings(.providers)
                } label: {
                    engineRow(
                        icon: controller.settings.transcriptionProvider.systemImage,
                        tint: controller.settings.transcriptionProvider.tint,
                        title: L("menu.engine", "Speech engine"),
                        value: controller.transcriptionSummary
                    ) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 40)

                engineRow(
                    icon: controller.settings.rewriteEnabled ? controller.settings.rewriteMode.systemImage : "text.alignleft",
                    tint: .purple,
                    title: L("menu.rewrite_title", "AI rewrite"),
                    value: rewriteValue
                ) {
                    Menu {
                        Button {
                            controller.settings.rewriteEnabled = false
                        } label: {
                            if controller.settings.rewriteEnabled {
                                Text(L("rewrite.off", "Off — raw transcript"))
                            } else {
                                Label(L("rewrite.off", "Off — raw transcript"), systemImage: "checkmark")
                            }
                        }
                        Divider()
                        ForEach(RewriteMode.allCases) { mode in
                            Button {
                                controller.settings.rewriteMode = mode
                                controller.settings.rewriteEnabled = true
                            } label: {
                                if controller.settings.rewriteEnabled && controller.settings.rewriteMode == mode {
                                    Label(mode.localizedName, systemImage: "checkmark")
                                } else {
                                    Text(mode.localizedName)
                                }
                            }
                        }
                    } label: {
                        Text(L("menu.change", "Change"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.visible)
                    .fixedSize()
                }
            }
        }
    }

    private func engineRow<Accessory: View>(icon: String, tint: Color, title: String, value: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            accessory()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    // MARK: - Results

    private func lastResultCard(_ result: DictationResult) -> some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(L("menu.last_result", "Last Result"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if result.rawText != nil {
                        Chip(text: L("menu.rewritten_chip", "Rewritten"), systemImage: "sparkles", tint: .purple)
                    }
                    Spacer()
                    Text(String(format: "%.1fs", result.latency))
                        .font(.system(size: 10, design: .rounded).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Button {
                        ClipboardWriter.write(result.text)
                    } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help(L("history.copy_tooltip", "Copy to clipboard"))
                }
                Text(result.text)
                    .font(.system(size: 12))
                    .lineLimit(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(history.entries.dropFirst(controller.lastResult == nil ? 0 : 1).prefix(3))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(L("menu.recent", "Recent"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(L("menu.see_all", "See All")) {
                        closeMenu()
                        controller.showHistory()
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                }
                ForEach(recent) { entry in
                    Button {
                        ClipboardWriter.write(entry.text)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.sourceIcon)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .frame(width: 14)
                            Text(entry.text)
                                .font(.system(size: 11.5))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 4)
                            Text(entry.date, style: .relative)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(L("menu.recent_hint", "Click to copy"))
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        GlassGroup(spacing: 6) {
            HStack(spacing: 6) {
                Button {
                    closeMenu()
                    controller.transcribeFile()
                } label: {
                    Label(L("menu.transcribe_file_short", "File…"), systemImage: "doc.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()
                .disabled(!controller.status.canStartRecording)
                .help(L("menu.transcribe_file", "Transcribe File…") + " " + L("menu.drop_hint", "You can also drop a file here."))

                Button {
                    closeMenu()
                    controller.showHistory()
                } label: {
                    Label(L("menu.history", "History"), systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .glassButton()
                .help(L("menu.quit", "Quit"))
            }
            .controlSize(.regular)
        }
    }

    private var dropOverlay: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.accentColor.opacity(0.08)))
            .overlay {
                Label(L("menu.drop_title", "Drop to transcribe"), systemImage: "arrow.down.doc.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(6)
            .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func recordTapped() {
        let starting = controller.status != .recording
        if starting { closeMenu() }
        controller.toggleRecording()
        if starting { controller.returnFocusToTarget() }
    }

    /// Dismisses the menu bar window.
    private func closeMenu() {
        NSApp.keyWindow?.close()
    }

    private var recordIcon: String {
        if controller.status == .recording { return "stop.fill" }
        return controller.settings.audioSource == .systemAudio ? "speaker.wave.2.fill" : "mic.fill"
    }

    private var recordTitle: String {
        if controller.status == .recording { return L("menu.stop_recording", "Stop & Transcribe") }
        if controller.status.isProcessing { return controller.status.statusText }
        return controller.settings.audioSource == .systemAudio
            ? L("menu.start_capture", "Capture System Audio")
            : L("menu.start_recording", "Start Dictation")
    }

    private var hint: String {
        if controller.settings.hotkey.isFunctionKey {
            return controller.settings.holdToTalkEnabled
                ? L("menu.hint.fn_hold", "Hold fn to dictate, or tap fn to start and stop · Esc cancels")
                : L("menu.hint.fn_toggle", "Tap fn to start and stop dictation · Esc cancels")
        }
        if controller.settings.holdToTalkEnabled {
            return L("menu.hint.hold", "Hold %@ to talk, or tap to start and stop · Esc cancels", controller.settings.hotkey.displayName)
        }
        return L("menu.hint.toggle", "Press %@ to start and stop · Esc cancels", controller.settings.hotkey.displayName)
    }

    private var statusLine: String {
        switch controller.status {
        case .idle:
            return controller.isTranscriptionConfigured
                ? L("status.ready", "Ready")
                : L("status.needs_setup", "Needs an API key")
        default:
            return controller.status.statusText
        }
    }

    private var rewriteValue: String {
        guard controller.settings.rewriteEnabled else { return L("rewrite.off_short", "Off") }
        let provider = controller.settings.rewriteProvider
        return "\(controller.settings.rewriteMode.localizedName) · \(provider.shortName)"
    }

    private func actionTitle(_ action: DictationFailure.Action) -> String {
        switch action {
        case .retry:          return L("action.retry", "Retry")
        case .openProviders:  return L("action.add_key", "Add Key")
        case .openPermission: return L("action.open_settings", "Open Settings")
        }
    }

    /// The permissions whose absence stops the selected source from working.
    private var permissionWarnings: [PermissionKind] {
        var kinds: [PermissionKind] = []
        switch controller.settings.audioSource {
        case .microphone:
            if !permissions.isGranted(.microphone) { kinds.append(.microphone) }
        case .systemAudio:
            if !permissions.isGranted(.screenRecording) { kinds.append(.screenRecording) }
        }
        if !permissions.isGranted(.accessibility) { kinds.append(.accessibility) }
        return kinds
    }

    private var statusColor: Color {
        switch controller.status {
        case .idle:                    return controller.isTranscriptionConfigured ? .green : .orange
        case .recording:               return .red
        case .transcribing, .rewriting: return .orange
        case .pasting, .done:          return .blue
        case .error:                   return .red
        }
    }
}
