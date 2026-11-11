import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import ServiceManagement
import os.log
import UserNotifications
import Combine

private let log = Logger(subsystem: "com.whisperfly", category: "AppController")

/// What the last successful dictation produced.
struct DictationResult: Equatable {
    let text: String
    /// The transcript before rewriting; `nil` when no rewrite changed it.
    let rawText: String?
    let source: TranscriptionEntry.Source
    let fileName: String?
    let provider: String
    let latency: TimeInterval
    let delivery: PipelineStatus.Delivery
    let date: Date
}

/// Why the last dictation failed, and what the user can do about it.
struct DictationFailure: Equatable {
    enum Action: Equatable {
        case retry
        case openProviders
        case openPermission(PermissionKind)
    }

    let message: String
    let action: Action?
}

/// Owns the dictation pipeline: hotkey → record → transcribe → rewrite →
/// insert, plus the windows around it.
///
/// Flow changes from 2.x worth knowing about:
///
/// - **Hold or tap.** Holding the shortcut records until release; a quick tap
///   toggles, as before.
/// - **Escape cancels** recording or transcription from any app; the key is only
///   claimed while something is in flight.
/// - **Errors never lock the hotkey.** An error used to leave the pipeline in
///   `.error` until "Dismiss" was clicked in the menu; now the next press simply
///   starts a new recording.
/// - **Failed recordings are kept for Retry** instead of being deleted, so a
///   network blip does not cost a two-minute dictation.
/// - **Fallback.** When the selected engine fails (bad key, rate limit, outage),
///   the next configured one is tried automatically.
@MainActor
final class AppController: ObservableObject {

    @Published private(set) var status: PipelineStatus = .idle {
        didSet { statusDidChange(from: oldValue) }
    }
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settingsDidChange(from: oldValue) } }
    }
    @Published private(set) var lastResult: DictationResult?
    @Published private(set) var lastFailure: DictationFailure?
    @Published private(set) var recordingStartedAt: Date?
    /// Secondary line for the pill, e.g. the engine currently transcribing.
    @Published private(set) var activityDetail: String = ""
    /// Problem registering the global shortcut, shown in the menu and settings.
    @Published private(set) var hotkeyError: String?

    let meter = AudioMeter()
    let history = TranscriptionHistory()
    let navigation = SettingsNavigation()

    /// The single authority on Microphone, Screen Recording and Accessibility.
    let permissions = PermissionService()

    /// Commit-based updater for the GitHub repository this build came from.
    let updates: UpdateService

    private let settingsStore = SettingsStore()
    private let audioService = AudioCaptureService()
    private let systemAudioService = SystemAudioCaptureService()
    private let hotkeyMonitor = HotkeyMonitor()
    private let fnMonitor = FnKeyMonitor()
    private var permissionObserver: AnyCancellable?
    private var pasteService: PasteService
    private let speechSynthesizer = AVSpeechSynthesizer()

    private let floatingPanel = FloatingPanel()
    private let resultPanel = TranscriptionResultPanel()
    private let historyPanel = HistoryPanel()
    private lazy var settingsWindow = SettingsWindowController(controller: self)
    private lazy var onboardingWindow = OnboardingWindowController(controller: self)

    /// The preset currently held by `hotkeyMonitor`.
    private var registeredHotkey: AppSettings.HotkeyPreset?

    // Recording state
    /// The source being recorded right now (Fn always records the microphone).
    @Published private(set) var activeAudioSource: AppSettings.AudioSource?
    private var targetApp: NSRunningApplication?
    private var lastExternalApp: NSRunningApplication?
    /// Set when system-audio capture delivered at least one non-silent buffer,
    /// to detect the macOS 26 SCStream silent-dropout bug.
    private var systemAudioHadSignal = false
    private var startTask: Task<Void, Never>?
    private var pipelineTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    // Hotkey hold-to-talk tracking
    private var hotkeyIsDown = false
    private var hotkeyDownAt: Date?
    private var recordingStartedByThisPress = false
    /// Fn pressed during a recording: stop on release, unless it becomes a chord.
    private var fnStopsOnRelease = false
    private static let holdThreshold: TimeInterval = 0.45

    /// Incremented whenever a dictation starts or is cancelled; async work from
    /// an older generation never touches the UI.
    private var generation = 0
    /// The audio of the last failed dictation, kept for Retry.
    private var retryJob: DictationJob?

    private struct DictationJob {
        let audioURL: URL
        let source: TranscriptionEntry.Source
        let fileName: String?
        let targetApp: NSRunningApplication?
        /// Recordings are ours to delete; a user's file never is.
        let ownsAudio: Bool
    }

    init() {
        let loaded = SettingsStore().load()
        self.settings = loaded
        self.pasteService = PasteService(pasteDelayMs: loaded.pasteDelayMs)
        self.updates = UpdateService(configuration: Self.updateConfiguration(from: loaded))

        Self.removeStaleRecordings()
        setupAudioCallbacks()
        setupHotkey()
        observeWorkspace()
        requestNotificationAuthorization()

        Task { await permissions.refreshAll() }
        Task { await updates.checkIfDue() }

        if !loaded.hasCompletedOnboarding {
            // Defer until the app has finished launching so the window can activate.
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        }
    }

    /// Projects the persisted settings onto the updater's configuration.
    static func updateConfiguration(from settings: AppSettings) -> UpdateService.Configuration {
        UpdateService.Configuration(
            repository: settings.updateRepository,
            branch: settings.updateBranch,
            token: settings.updateToken,
            sourceCheckoutPath: settings.updateSourceCheckoutPath,
            automaticallyChecks: settings.updateAutomaticallyChecks,
            checkIntervalHours: settings.updateCheckIntervalHours
        )
    }

    // MARK: - Derived state

    /// Something can transcribe: the selected engine, or a fallback.
    var isTranscriptionConfigured: Bool {
        ProviderFactory.transcriptionChain(for: settings).contains { settings.isConfigured($0) }
    }

    var canRetry: Bool { retryJob != nil && status.canStartRecording }

    var transcriptionSummary: String {
        let provider = settings.transcriptionProvider
        return "\(provider.shortName) · \(settings.transcriptionModel(for: provider))"
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Windows

    func showHistory() {
        historyPanel.toggle(controller: self, resultPanel: resultPanel)
    }

    func showResult(for entry: TranscriptionEntry) {
        resultPanel.show(entry: entry)
    }

    func openSettings(_ section: SettingsSection? = nil) {
        if let section { navigation.selection = section }
        settingsWindow.show()
    }

    func showOnboarding() {
        onboardingWindow.show()
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        onboardingWindow.close()
    }

    // MARK: - Workspace

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
                self.lastExternalApp = app
            }
        }
        // Re-check permissions when the user comes back from System Settings.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                // Re-read system state the user may have changed meanwhile
                // (permissions, the Fn key's own action).
                self?.objectWillChange.send()
                await self?.permissions.refreshOnActivation()
            }
        }
    }

    /// The app text should go to: the frontmost one, unless that is WhisperFly
    /// itself (recording started from the menu bar window), in which case the
    /// app the user was in before.
    private func resolveTargetApp() -> NSRunningApplication? {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let front = NSWorkspace.shared.frontmostApplication else { return lastExternalApp }
        if front.processIdentifier != ownPID { return front }
        // Dictating into WhisperFly's own window (the welcome guide's practice
        // field) is fine; the borderless menu bar window is not a destination.
        if NSApp.keyWindow?.styleMask.contains(.titled) == true { return front }
        return lastExternalApp
    }

    /// Inserts into one of WhisperFly's own text views directly. Accessibility
    /// calls into the calling process block its main thread, so the AX path
    /// must never be used on ourselves.
    private func insertIntoOwnWindow(_ text: String) -> Bool {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isEditable else { return false }
        textView.insertText(text, replacementRange: textView.selectedRange())
        return true
    }

    // MARK: - Notifications

    private func requestNotificationAuthorization() {
        // `UNUserNotificationCenter` raises an exception in a bundle-less
        // `swift run` process.
        guard BuildInfo.isAppBundle else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func showNotification(title: String, body: String) {
        guard BuildInfo.isAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyMonitor.onPress = { [weak self] in
            Task { @MainActor in self?.hotkeyPressed() }
        }
        hotkeyMonitor.onRelease = { [weak self] in
            Task { @MainActor in self?.hotkeyReleased() }
        }
        hotkeyMonitor.onCancel = { [weak self] in
            Task { @MainActor in self?.cancelCurrentOperation() }
        }
        fnMonitor.onPress = { [weak self] in self?.fnPressed() }
        fnMonitor.onRelease = { [weak self] wasChord in self?.fnReleased(wasChord: wasChord) }
        fnMonitor.onChord = { [weak self] in self?.fnChordDetected() }
        // Global key monitors only work once Accessibility is granted, and
        // must be reinstalled after the grant arrives.
        permissionObserver = permissions.$states.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fnMonitor.restartIfTrustChanged() }
        }
        reregisterHotkeyIfNeeded()
    }

    private func reregisterHotkeyIfNeeded() {
        guard registeredHotkey != settings.hotkey else { return }
        if settings.hotkey.isFunctionKey {
            hotkeyMonitor.unregisterShortcut()
            fnMonitor.start()
            registeredHotkey = settings.hotkey
            hotkeyError = nil
            return
        }
        fnMonitor.stop()
        do {
            try hotkeyMonitor.register(preset: settings.hotkey)
            registeredHotkey = settings.hotkey
            hotkeyError = nil
        } catch {
            registeredHotkey = nil
            hotkeyError = error.localizedDescription
            log.error("Hotkey registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func hotkeyPressed() {
        // Carbon can repeat the press while the chord is held.
        guard !hotkeyIsDown else { return }
        hotkeyIsDown = true
        hotkeyDownAt = Date()

        if status == .recording {
            recordingStartedByThisPress = false
            finishRecording()
        } else if status.canStartRecording {
            startRecording()
            recordingStartedByThisPress = status == .recording
        }
    }

    /// Releasing after a deliberate hold ends the recording (push-to-talk); a
    /// quick tap leaves it running until the next press (toggle).
    private func hotkeyReleased() {
        hotkeyIsDown = false
        defer { recordingStartedByThisPress = false }
        guard settings.holdToTalkEnabled,
              recordingStartedByThisPress,
              status == .recording,
              let downAt = hotkeyDownAt,
              Date().timeIntervalSince(downAt) >= Self.holdThreshold else { return }
        finishRecording()
    }

    // MARK: - Fn key

    /// Fn dictates from the microphone whatever source the menu has selected.
    /// Pressing it during a recording stops on *release*, so Fn+Delete or
    /// Fn+arrow typed mid-recording does not end the dictation.
    private func fnPressed() {
        hotkeyDownAt = Date()
        if status == .recording {
            recordingStartedByThisPress = false
            fnStopsOnRelease = true
            return
        }
        guard status.canStartRecording else { return }
        startRecording(source: .microphone, deferFeedback: true)
        recordingStartedByThisPress = status == .recording
    }

    private func fnReleased(wasChord: Bool) {
        defer {
            recordingStartedByThisPress = false
            fnStopsOnRelease = false
        }
        // An Fn press that started nothing and became a chord is just a shortcut.
        if wasChord && !recordingStartedByThisPress && !fnStopsOnRelease { return }
        if fnStopsOnRelease {
            finishRecording()
            return
        }
        guard settings.holdToTalkEnabled,
              recordingStartedByThisPress,
              status == .recording,
              let downAt = hotkeyDownAt,
              Date().timeIntervalSince(downAt) >= Self.holdThreshold else { return }
        finishRecording()
    }

    /// Fn was the modifier of a key combination, not a dictation press.
    ///
    /// Right after the press that almost certainly means Fn+Delete, Fn+arrow
    /// and the like, so the recording is discarded silently. Later in a long
    /// hold it is a stray key, and the dictation carries on to the release.
    private func fnChordDetected() {
        fnStopsOnRelease = false
        guard recordingStartedByThisPress, status == .recording,
              let downAt = hotkeyDownAt, Date().timeIntervalSince(downAt) < 1.0 else { return }
        recordingStartedByThisPress = false
        cancelCurrentOperation()
    }

    /// What macOS does with Fn, when that would fire alongside dictation.
    var fnKeyConflict: SystemFnKeyAction? {
        guard settings.hotkey.isFunctionKey else { return nil }
        let action = SystemFnKeyAction.current
        return action.conflictsWithDictation ? action : nil
    }

    // MARK: - Audio callbacks

    private func setupAudioCallbacks() {
        audioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
        audioService.onAudioLevel = { [weak self] level in
            Task { @MainActor in self?.meter.push(dBFS: level) }
        }
        audioService.onMaxDurationReached = { [weak self] in
            Task { @MainActor in self?.finishRecording() }
        }

        systemAudioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
        systemAudioService.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.meter.push(dBFS: level)
                if level > -50 { self.systemAudioHadSignal = true }
            }
        }
        systemAudioService.onMaxDurationReached = { [weak self] in
            Task { @MainActor in self?.finishRecording() }
        }
    }

    // MARK: - Recording

    func toggleRecording() {
        if status == .recording {
            finishRecording()
        } else if status.canStartRecording {
            startRecording()
        }
    }

    /// Starting from the menu bar window leaves WhisperFly focused; hand focus
    /// back to the app the text is for so the user can keep their place.
    func returnFocusToTarget() {
        guard status == .recording, let app = targetApp, !app.isTerminated else { return }
        app.activate()
    }

    /// Starts recording from `source` (the menu's selection when `nil`).
    ///
    /// `deferFeedback` holds back the pill and the start sound for a moment, so
    /// an Fn press that turns into Fn+key cancels without a flash or a chime.
    func startRecording(source requestedSource: AppSettings.AudioSource? = nil, deferFeedback: Bool = false) {
        guard status.canStartRecording else { return }

        guard isTranscriptionConfigured else {
            present(failure: DictationFailure(
                message: PipelineError.notConfigured(settings.transcriptionProvider).localizedDescription,
                action: .openProviders
            ))
            return
        }

        let source = requestedSource ?? settings.audioSource
        guard verifyPermission(source == .microphone ? .microphone : .screenRecording) else { return }

        discardRetry()
        generation += 1
        let currentGeneration = generation
        hideTask?.cancel()

        targetApp = source == .microphone ? resolveTargetApp() : nil
        activeAudioSource = source
        systemAudioHadSignal = false
        lastFailure = nil
        activityDetail = ""
        meter.reset()
        recordingStartedAt = Date()
        status = .recording
        if deferFeedback {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(180))
                guard let self, self.generation == currentGeneration, self.status == .recording else { return }
                self.floatingPanel.show(with: self)
                if self.settings.soundEffectsEnabled { SoundEffects.play(.start) }
            }
        } else {
            floatingPanel.show(with: self)
            if settings.soundEffectsEnabled { SoundEffects.play(.start) }
        }

        startTask = Task {
            do {
                switch source {
                case .microphone:  _ = try await audioService.startRecording()
                case .systemAudio: _ = try await systemAudioService.startRecording()
                }
            } catch {
                guard currentGeneration == generation else { return }
                log.error("startRecording failed: \(error.localizedDescription, privacy: .public)")
                activeAudioSource = nil
                recordingStartedAt = nil
                // Code 30 is the Screen Recording refusal from SystemAudioCaptureService.
                let nsError = error as NSError
                if nsError.domain == "WhisperFly" && nsError.code == 30 {
                    present(failure: DictationFailure(message: error.localizedDescription, action: .openPermission(.screenRecording)))
                } else {
                    present(failure: DictationFailure(message: error.localizedDescription, action: nil))
                }
            }
        }
    }

    /// Decides whether a recording may start for `kind`, prompting or refusing as
    /// appropriate. Screen Recording may legitimately be `.unknown` (its preflight
    /// has false negatives), in which case the capture attempt decides.
    private func verifyPermission(_ kind: PermissionKind) -> Bool {
        switch permissions.state(for: kind) {
        case .granted, .unknown:
            return true
        case .notDetermined:
            Task { await permissions.request(kind) }
            return true
        case .denied, .restricted:
            let message = L("error.permission_required",
                            "%@ permission is required for this audio source. Enable it in System Settings, then try again.",
                            kind.title)
            present(failure: DictationFailure(message: message, action: .openPermission(kind)))
            return false
        }
    }

    func finishRecording() {
        guard status == .recording else { return }

        let source = activeAudioSource ?? .microphone
        let hadSignal = systemAudioHadSignal
        let startedAt = recordingStartedAt
        activeAudioSource = nil
        recordingStartedAt = nil
        systemAudioHadSignal = false
        if settings.soundEffectsEnabled { SoundEffects.play(.stop) }

        status = .transcribing
        activityDetail = ""
        let currentGeneration = generation
        let pendingStart = startTask
        let target = targetApp

        pipelineTask = Task {
            await pendingStart?.value
            guard currentGeneration == generation else { return }

            let url: URL
            do {
                switch source {
                case .microphone:  url = try await audioService.stopRecording()
                case .systemAudio: url = try await systemAudioService.stopRecording()
                }
            } catch {
                guard currentGeneration == generation else { return }
                present(failure: DictationFailure(message: error.localizedDescription, action: nil))
                return
            }

            // A press-and-immediately-release is almost always accidental.
            if let startedAt, Date().timeIntervalSince(startedAt) < 0.3 {
                try? FileManager.default.removeItem(at: url)
                if currentGeneration == generation { finish(hidingAfter: 0) }
                return
            }

            if source == .systemAudio && !hadSignal {
                log.warning("System audio recording contained no signal — possible macOS 26 SCStream dropout")
                showNotification(
                    title: L("notify.silent.title", "Silent Recording Detected"),
                    body: L("notify.silent.body", "No audio signal was captured. Quit other screen-recording apps, toggle System Audio off and on, or restart WhisperFly.")
                )
            }

            await process(
                DictationJob(
                    audioURL: url,
                    source: source == .microphone ? .microphone : .systemAudio,
                    fileName: nil,
                    targetApp: target,
                    ownsAudio: true
                ),
                generation: currentGeneration
            )
        }
    }

    /// Escape, the pill's ✕, and the menu's Cancel all land here.
    func cancelCurrentOperation() {
        switch status {
        case .recording:
            generation += 1
            let source = activeAudioSource
            activeAudioSource = nil
            recordingStartedAt = nil
            let pendingStart = startTask
            Task {
                await pendingStart?.value
                switch source {
                case .systemAudio: await systemAudioService.cancelRecording()
                default:           await audioService.cancelRecording()
                }
            }
            targetApp = nil
            finish(hidingAfter: 0)

        case .transcribing, .rewriting, .pasting:
            generation += 1
            pipelineTask?.cancel()
            pipelineTask = nil
            targetApp = nil
            finish(hidingAfter: 0)

        case .error, .done:
            finish(hidingAfter: 0)

        case .idle:
            break
        }
    }

    // MARK: - Files

    /// Opens a picker for audio or video and transcribes the choice.
    func transcribeFile() {
        guard status.canStartRecording else { return }
        NSApp.activate()

        let panel = NSOpenPanel()
        panel.title = L("file.pick_title", "Select Audio or Video File")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.mediaContentTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        transcribe(fileURL: url)
    }

    /// Transcribes a media file; the result goes to the clipboard and a result window.
    func transcribe(fileURL url: URL) {
        guard status.canStartRecording else { return }
        guard isTranscriptionConfigured else {
            present(failure: DictationFailure(
                message: PipelineError.notConfigured(settings.transcriptionProvider).localizedDescription,
                action: .openProviders
            ))
            return
        }

        discardRetry()
        generation += 1
        let currentGeneration = generation
        hideTask?.cancel()
        lastFailure = nil
        activityDetail = url.lastPathComponent
        status = .transcribing
        floatingPanel.show(with: self)

        pipelineTask = Task {
            await process(
                DictationJob(audioURL: url, source: .file, fileName: url.lastPathComponent, targetApp: nil, ownsAudio: false),
                generation: currentGeneration
            )
        }
    }

    static let mediaContentTypes: [UTType] = {
        var types: [UTType] = [.audio, .movie]
        for ext in AudioConverter.supportedAudioExtensions + AudioConverter.supportedVideoExtensions {
            if let type = UTType(filenameExtension: ext) { types.append(type) }
        }
        return types
    }()

    // MARK: - Retry

    func retryLastDictation() {
        guard let job = retryJob, status.canStartRecording else { return }
        retryJob = nil
        generation += 1
        let currentGeneration = generation
        hideTask?.cancel()
        lastFailure = nil
        status = .transcribing
        floatingPanel.show(with: self)
        pipelineTask = Task { await process(job, generation: currentGeneration) }
    }

    private func discardRetry() {
        if let job = retryJob, job.ownsAudio {
            try? FileManager.default.removeItem(at: job.audioURL)
        }
        retryJob = nil
    }

    // MARK: - Pipeline

    private func process(_ job: DictationJob, generation jobGeneration: Int) async {
        let temporary = TemporaryFiles()
        defer { temporary.removeAll() }
        func isCurrent() -> Bool { jobGeneration == generation }

        do {
            let wav = try await AudioConverter.prepareWAV(from: job.audioURL)
            temporary.add(wav.url)
            try Task.checkCancellation()

            // Nothing audible was captured: do not spend a request on silence.
            guard wav.duration >= 0.2, wav.peakDBFS > -58 else { throw PipelineError.noSpeech }

            let transcription = try await transcribe(wav, temporary: temporary, isCurrent: isCurrent)
            let rawText = TranscriptFilter.clean(transcription.text)
            guard !rawText.isEmpty else { throw PipelineError.noSpeech }
            try Task.checkCancellation()

            var finalText = rawText
            var latency = transcription.latency
            var translated = false
            if shouldRewrite(after: transcription), isCurrent() {
                status = .rewriting
                activityDetail = settings.rewriteMode.localizedName
                if let rewrite = await rewrite(rawText, appName: job.targetApp?.localizedName) {
                    finalText = rewrite.rewrittenText
                    latency += rewrite.latency
                    translated = settings.rewriteMode == .translate
                }
            }
            try Task.checkCancellation()
            guard isCurrent() else { return }

            status = .pasting
            let delivery = await deliver(finalText, for: job)
            guard isCurrent() else { return }

            history.add(TranscriptionEntry(
                text: finalText,
                source: job.source,
                fileName: job.fileName,
                latency: latency,
                rawText: rawText,
                provider: transcription.providerName,
                duration: wav.duration
            ))
            lastResult = DictationResult(
                text: finalText,
                rawText: finalText == rawText ? nil : rawText,
                source: job.source,
                fileName: job.fileName,
                provider: transcription.providerName,
                latency: latency,
                delivery: delivery,
                date: Date()
            )

            if job.source != .microphone, let entry = history.entries.first {
                resultPanel.show(entry: entry)
            }
            if settings.readAloudEnabled {
                readAloud(finalText, language: translated ? settings.translationTarget : settings.language)
            }
            if job.ownsAudio { try? FileManager.default.removeItem(at: job.audioURL) }

            targetApp = nil
            status = .done(delivery)
            finish(hidingAfter: job.source == .microphone ? 1.1 : 0.6)

        } catch is CancellationError {
            if job.ownsAudio { try? FileManager.default.removeItem(at: job.audioURL) }
        } catch PipelineError.noSpeech {
            if job.ownsAudio { try? FileManager.default.removeItem(at: job.audioURL) }
            guard isCurrent() else { return }
            present(failure: DictationFailure(message: PipelineError.noSpeech.localizedDescription, action: nil))
        } catch {
            guard isCurrent() else {
                if job.ownsAudio { try? FileManager.default.removeItem(at: job.audioURL) }
                return
            }
            log.error("Dictation failed: \(error.localizedDescription, privacy: .public)")
            retryJob = job
            let action: DictationFailure.Action
            switch error as? ProviderError {
            case .missingKey?, .invalidKey?: action = .openProviders
            default:                         action = .retry
            }
            present(failure: DictationFailure(message: error.localizedDescription, action: action))
        }
    }

    /// Runs the transcription chain: the selected engine, then fallbacks.
    private func transcribe(
        _ wav: PreparedAudio,
        temporary: TemporaryFiles,
        isCurrent: () -> Bool
    ) async throws -> TranscriptionResultPayload {
        var compressed: PreparedAudio?
        var failures: [Error] = []

        for provider in ProviderFactory.transcriptionChain(for: settings) {
            guard settings.isConfigured(provider) else {
                failures.append(ProviderError.missingKey(provider))
                continue
            }
            let recognizer = ProviderFactory.recognizer(for: provider, settings: settings)
            if isCurrent() { activityDetail = recognizer.displayName }

            do {
                var audio = wav
                if wav.byteCount > recognizer.maxUploadBytes {
                    if compressed == nil {
                        let aac = try await AudioConverter.compressToAAC(wav)
                        temporary.add(aac.url)
                        compressed = aac
                    }
                    guard let aac = compressed, aac.byteCount <= recognizer.maxUploadBytes else {
                        throw ProviderError.audioTooLarge(provider, limitMB: recognizer.maxUploadBytes / 1_048_576)
                    }
                    audio = aac
                }
                return try await recognizer.transcribe(audio: audio)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ProviderError where error.warrantsFallback {
                log.warning("\(provider.rawValue, privacy: .public) failed, trying next: \(error.localizedDescription, privacy: .public)")
                failures.append(error)
            }
        }
        // Report the selected engine's problem, not the last fallback's.
        throw failures.first ?? PipelineError.notConfigured(settings.transcriptionProvider)
    }

    private func shouldRewrite(after transcription: TranscriptionResultPayload) -> Bool {
        guard settings.rewriteEnabled, settings.isConfigured(settings.rewriteProvider) else { return false }
        // Gemini's smart transcription already did what Cleanup would do.
        if transcription.isAlreadyPolished && settings.rewriteMode == .cleanup { return false }
        return true
    }

    /// The rewritten text, or `nil` to keep the raw transcript. A rewrite
    /// failure never fails the dictation.
    private func rewrite(_ text: String, appName: String?) async -> RewriteResultPayload? {
        let rewriter = ProviderFactory.rewriter(for: settings.rewriteProvider, settings: settings)
        let prompt = RewritePrompts.systemPrompt(.init(
            mode: settings.rewriteMode,
            targetLanguage: settings.translationTarget,
            customInstructions: settings.customSystemPrompt,
            vocabulary: settings.vocabularyTerms,
            appName: appName
        ))
        do {
            let result = try await rewriter.rewrite(inputText: text, systemPrompt: prompt)
            guard !result.rewrittenText.isEmpty else { return nil }
            if RewriteOutput.looksLikeAnAnswer(source: text, rewritten: result.rewrittenText, mode: settings.rewriteMode) {
                log.warning("Rewrite looked like an answer rather than an edit; keeping the transcript")
                return nil
            }
            return result
        } catch {
            log.error("Rewrite failed, keeping the raw transcript: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Types the text into the target app, or puts it on the clipboard.
    private func deliver(_ text: String, for job: DictationJob) async -> PipelineStatus.Delivery {
        guard job.source == .microphone else {
            ClipboardWriter.write(text)
            return .copied
        }

        if job.targetApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            if insertIntoOwnWindow(text) { return .inserted }
            ClipboardWriter.write(text)
            return .copied
        }

        // Without Accessibility neither AX writes nor the synthetic ⌘V can
        // reach another app, and the paste path would restore the old clipboard
        // over the transcript. Leave the text on the clipboard instead.
        guard PermissionService.probeAccessibility() == .granted else {
            ClipboardWriter.write(text)
            return .copied
        }

        if let app = job.targetApp, !app.isTerminated {
            app.activate()
            try? await Task.sleep(for: .milliseconds(180))
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                app.activate()
                try? await Task.sleep(for: .milliseconds(200))
            }
        } else {
            try? await Task.sleep(for: .milliseconds(settings.pasteDelayMs))
        }

        let pid = job.targetApp?.processIdentifier
        do {
            switch settings.insertionMethod {
            case .automatic:
                _ = try pasteService.insert(text: text, targetPID: pid)
            case .paste:
                try pasteService.clipboardInsert(text, targetPID: pid)
            }
            return .inserted
        } catch {
            log.error("Insert failed: \(error.localizedDescription, privacy: .public)")
            ClipboardWriter.write(text)
            return .copied
        }
    }

    private func readAloud(_ text: String, language: DictationLanguage) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = language.isAuto ? nil : AVSpeechSynthesisVoice(language: language.code)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    // MARK: - Status plumbing

    private func present(failure: DictationFailure) {
        lastFailure = failure
        status = .error(failure.message)
        if settings.soundEffectsEnabled { SoundEffects.play(.error) }
        floatingPanel.show(with: self)
        finish(hidingAfter: 6, onlyIfError: true)
    }

    /// Returns to idle and hides the pill after `delay`.
    private func finish(hidingAfter delay: TimeInterval, onlyIfError: Bool = false) {
        hideTask?.cancel()
        if delay <= 0 {
            status = .idle
            floatingPanel.hide()
            return
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            if onlyIfError && !self.status.isError { return }
            if self.status.canStartRecording {
                self.status = .idle
                self.floatingPanel.hide()
            }
        }
    }

    func dismissFailure() {
        lastFailure = nil
        if status.isError { finish(hidingAfter: 0) }
    }

    func perform(_ action: DictationFailure.Action) {
        switch action {
        case .retry:
            retryLastDictation()
        case .openProviders:
            dismissFailure()
            openSettings(.providers)
        case .openPermission(let kind):
            dismissFailure()
            permissions.openSettings(for: kind)
        }
    }

    private func statusDidChange(from old: PipelineStatus) {
        // Escape belongs to WhisperFly only while there is something to cancel.
        if status.isBusy && !old.isBusy {
            hotkeyMonitor.registerCancelKey()
        } else if !status.isBusy && old.isBusy {
            hotkeyMonitor.unregisterCancelKey()
        }
    }

    // MARK: - Settings

    private func settingsDidChange(from old: AppSettings) {
        settingsStore.save(settings)
        if settings.pasteDelayMs != old.pasteDelayMs {
            pasteService = PasteService(pasteDelayMs: settings.pasteDelayMs)
        }
        if settings.maxRecordingSeconds != old.maxRecordingSeconds {
            audioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
            systemAudioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
        }
        let configuration = Self.updateConfiguration(from: settings)
        if updates.configuration != configuration {
            updates.configuration = configuration
        }
        reregisterHotkeyIfNeeded()
    }

    // MARK: - Permissions and updates (UI entry points)

    /// Clears this app's TCC rows and relaunches. The only reliable remedy when
    /// the build was re-signed and macOS still holds rows for the old signature.
    @discardableResult
    func repairPermissionsAndRelaunch() -> String? {
        let failures = PermissionRepair.resetAll(bundleIdentifier: BuildInfo.bundleIdentifier)
        guard failures.isEmpty else {
            let names = failures.map(\.title).joined(separator: ", ")
            return L("permission.repair.partial",
                     "Could not reset: %@. Try again, or remove WhisperFly from the Privacy lists manually.", names)
        }
        PermissionRepair.relaunch()
        return nil
    }

    func requestPermission(_ kind: PermissionKind) {
        Task {
            await permissions.request(kind)
            if kind.requiresRelaunchToTakeEffect && permissions.isGranted(kind) {
                showNotification(
                    title: kind.title,
                    body: L("permission.relaunch_hint", "Granted. WhisperFly needs to restart before this takes effect.")
                )
            }
        }
    }

    func checkForUpdatesNow() {
        Task { await updates.check() }
    }

    func installUpdate(using method: UpdateInstallMethod) {
        Task { await updates.install(using: method) }
    }

    // MARK: - Housekeeping

    /// Recordings only outlive a dictation as Retry material, which does not
    /// survive a relaunch; anything left over is from a crash.
    private static func removeStaleRecordings() {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperFly/Recordings", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }
}

/// Collects temporary files and removes them together.
private final class TemporaryFiles {
    private var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
    func removeAll() {
        for url in urls { try? FileManager.default.removeItem(at: url) }
        urls.removeAll()
    }
}

/// Short system sounds for start, stop and failure.
enum SoundEffects {
    enum Cue: String {
        case start = "Tink"
        case stop = "Pop"
        case error = "Funk"
    }

    @MainActor
    static func play(_ cue: Cue) {
        guard let sound = NSSound(named: NSSound.Name(cue.rawValue)) else { return }
        sound.volume = cue == .error ? 0.25 : 0.35
        sound.stop()
        sound.play()
    }
}
