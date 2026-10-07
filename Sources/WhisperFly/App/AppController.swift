import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import os.log
import UserNotifications

private let log = Logger(subsystem: "com.whisperfly", category: "AppController")

@MainActor
final class AppController: ObservableObject {
    @Published var status: PipelineStatus = .idle
    @Published var audioLevel: Float = -160
    @Published var settings: AppSettings
    @Published var lastTranscription: String = ""
    @Published var lastRewrite: String = ""
    @Published var lastLatency: TimeInterval = 0
    @Published var errorMessage: String?

    private let settingsStore = SettingsStore()
    private var audioService = AudioCaptureService()
    private var systemAudioService = SystemAudioCaptureService()
    private var hotkeyMonitor = HotkeyMonitor()
    private var pasteService: PasteService
    private var currentRecordingURL: URL?
    private let floatingPanel = FloatingPanel()
    private let resultPanel = TranscriptionResultPanel()
    private let historyPanel = HistoryPanel()
    let history = TranscriptionHistory()
    private var hideTask: Task<Void, Never>?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var targetApp: NSRunningApplication?
    /// The preset currently held by `hotkeyMonitor`, so `saveSettings()` — which
    /// fires on every keystroke in the settings form — does not re-register the
    /// shortcut needlessly.
    private var registeredHotkey: AppSettings.HotkeyPreset?
    /// Tracks the file name when transcribing a file
    private var currentFileName: String?
    /// Set to `true` when the system-audio recording receives at least one
    /// non-silent sample (level > -50 dBFS).  Used to detect the macOS 26
    /// SCStream silent-audio dropout bug and show the user a useful warning.
    private var systemAudioHadSignal = false
    /// Snapshots which audio source was active when recording started.
    /// Using this instead of `settings.audioSource` at stop-time prevents
    /// the wrong service from being stopped if the user switches the source
    /// picker while a recording is in progress.
    private var activeAudioSource: AppSettings.AudioSource?

    /// The single authority on Microphone, Screen Recording and Accessibility.
    /// The controller previously kept its own pair of `Bool`s and a bespoke
    /// `CGPreflightScreenCaptureAccess()` call gated behind `#available(macOS 26)`;
    /// that version check is why the app believed permissions were granted on the
    /// releases it had not been updated for.
    let permissions = PermissionService()

    /// Commit-based updater for the GitHub repository this build came from.
    let updates: UpdateService

    init() {
        let loaded = SettingsStore().load()
        self.settings = loaded
        self.pasteService = PasteService(pasteDelayMs: loaded.pasteDelayMs)
        self.updates = UpdateService(configuration: Self.updateConfiguration(from: loaded))

        setupAudioCallbacks()
        setupHotkey()
        observeAppActivation()
        requestNotificationAuthorization()

        Task { await permissions.refreshAll() }
        Task { await updates.checkIfDue() }
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

    /// Re-checks permissions whenever the app becomes active — the moment a user
    /// normally returns from System Settings, so the menu bar reflects the change
    /// without needing a relaunch.
    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.permissions.refreshOnActivation()
            }
        }
    }

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - History & Result Panels

    func showHistory() {
        historyPanel.show(history: history, resultPanel: resultPanel)
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyMonitor.onPress = { [weak self] in
            Task { @MainActor in
                self?.hotkeyPressed()
            }
        }
        hotkeyMonitor.onRelease = { [weak self] in
            Task { @MainActor in
                self?.hotkeyReleased()
            }
        }
        reregisterHotkeyIfNeeded()
    }

    /// Re-registers the global shortcut when the preference actually changed.
    ///
    /// `saveSettings()` runs on every keystroke in the settings form, so this is
    /// deliberately idempotent rather than registering on each call.
    private func reregisterHotkeyIfNeeded() {
        guard registeredHotkey != settings.hotkey else { return }
        do {
            try hotkeyMonitor.register(preset: settings.hotkey)
            registeredHotkey = settings.hotkey
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            log.error("Hotkey registration failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setupAudioCallbacks() {
        audioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
        audioService.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                self?.audioLevel = level
            }
        }
        audioService.onMaxDurationReached = { [weak self] in
            Task { @MainActor in
                self?.finishRecording()
            }
        }

        systemAudioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
        systemAudioService.onAudioLevel = { [weak self] level in
            Task { @MainActor in
                guard let self else { return }
                self.audioLevel = level
                // Track whether any non-silent audio arrived (macOS 26 dropout guard).
                if level > -50 {
                    self.systemAudioHadSignal = true
                }
            }
        }
        systemAudioService.onMaxDurationReached = { [weak self] in
            Task { @MainActor in
                self?.finishRecording()
            }
        }
    }

    // MARK: - Recording Pipeline

    private func hotkeyPressed() {
        switch status {
        case .idle:
            startRecording()
        case .recording:
            finishRecording()
        default:
            break
        }
    }

    private func hotkeyReleased() {
        // Toggle mode: do nothing on release
    }

    func startRecording() {
        guard status == .idle else { return }

        let required: PermissionKind = settings.audioSource == .microphone ? .microphone : .screenRecording
        guard verifyPermission(required) else { return }

        if settings.audioSource == .microphone {
            targetApp = NSWorkspace.shared.frontmostApplication
        } else {
            targetApp = nil
        }

        status = .recording
        errorMessage = nil
        hideTask?.cancel()
        floatingPanel.show(with: self)

        activeAudioSource = settings.audioSource
        if settings.audioSource == .systemAudio {
            systemAudioHadSignal = false
        }

        Task {
            do {
                let url: URL
                switch activeAudioSource {
                case .microphone, nil:
                    url = try await audioService.startRecording()
                case .systemAudio:
                    url = try await systemAudioService.startRecording()
                }
                currentRecordingURL = url
            } catch {
                log.error("startRecording failed: \(error.localizedDescription)")
                status = .error(error.localizedDescription)
                // Code 30 is the Screen Recording permission error thrown by
                // SystemAudioCaptureService when SCShareableContent is denied.
                let nsErr = error as NSError
                if nsErr.domain == "WhisperFly" && nsErr.code == 30 {
                    showNotification(
                        title: "Screen Recording Required",
                        body: "Open System Settings → Privacy & Security → Screen Recording and enable WhisperFly, then try again."
                    )
                } else {
                    showNotification(title: "Recording Failed", body: error.localizedDescription)
                }
                floatingPanel.hide()
            }
        }
    }

    /// Decides whether a recording may start for `kind`, prompting or refusing as
    /// appropriate.
    ///
    /// Microphone state comes from `AVCaptureDevice.authorizationStatus`, which is
    /// synchronous and always current, so a denial is always acted upon. Screen
    /// Recording state can legitimately be `.unknown`: `CGPreflightScreenCaptureAccess()`
    /// has documented false negatives, so in that case the capture attempt itself is
    /// allowed to decide. The previous code reached the same conclusion, but only on
    /// the macOS version it had been updated for and by guessing afterwards.
    private func verifyPermission(_ kind: PermissionKind) -> Bool {
        switch permissions.state(for: kind) {
        case .granted, .unknown:
            return true

        case .notDetermined:
            // Ask, and let the capture attempt run: the system prompt is shown
            // immediately and the engine starts as soon as it is answered.
            Task { await permissions.request(kind) }
            return true

        case .denied, .restricted:
            refuseRecording(kind)
            return false
        }
    }

    private func refuseRecording(_ kind: PermissionKind) {
        let message = L("error.permission_required",
                        "%@ permission is required for this audio source. Enable it in System Settings, then try again.",
                        kind.title)
        status = .error(message)
        showNotification(title: kind.title, body: message)
        permissions.openSettings(for: kind)
    }

    func finishRecording() {
        guard status == .recording else { return }

        // Snapshot state before the async stop clears it.
        let hadSignal = systemAudioHadSignal
        let source = activeAudioSource   // use start-time source, not current setting
        activeAudioSource = nil
        systemAudioHadSignal = false

        Task {
            do {
                let url: URL
                switch source {
                case .microphone, nil:
                    url = try await audioService.stopRecording()
                case .systemAudio:
                    url = try await systemAudioService.stopRecording()
                    // macOS 26 SCStream bug: the stream starts but delivers only
                    // zero-valued samples, so the file contains no real audio.
                    // Warn the user before we send silence to the transcription API.
                    if !hadSignal {
                        log.warning("System audio recording contained no signal — possible macOS 26 SCStream dropout")
                        showNotification(
                            title: "Silent Recording Detected",
                            body: "No audio signal was captured. This is a known ScreenCaptureKit issue on macOS 26. Try: quit other screen-recording apps, toggle System Audio off/on, or restart WhisperFly."
                        )
                    }
                }
                currentRecordingURL = url
                await processAudio(url: url, source: source ?? .microphone)
            } catch {
                log.error("finishRecording failed: \(error.localizedDescription)")
                status = .error(error.localizedDescription)
                floatingPanel.hide()
            }
        }
    }

    func cancelCurrentOperation() {
        activeAudioSource = nil
        systemAudioHadSignal = false
        Task {
            await audioService.cancelRecording()
            await systemAudioService.cancelRecording()
        }
        status = .idle
        audioLevel = -160
        targetApp = nil
        floatingPanel.hide()
    }

    // MARK: - Transcription + Rewrite Pipeline

    private func processAudio(url: URL, source: AppSettings.AudioSource) async {
        status = .transcribing
        audioLevel = -160
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            let recognizer = makeRecognizer()
            let result = try await recognizer.transcribe(audioURL: url)
            lastTranscription = result.text

            guard !result.text.isEmpty else {
                status = .error("No speech detected")
                return
            }

            var finalText = result.text

            if settings.geminiRewriteEnabled, !settings.openRouterApiKey.isEmpty {
                status = .rewriting
                do {
                    let rewriter = GeminiRewriter(apiKey: settings.openRouterApiKey, model: settings.openRouterModel)
                    let rewriteResult = try await rewriter.rewrite(
                        inputText: result.text,
                        locale: Locale.current,
                        mode: settings.rewriteMode
                    )
                    lastRewrite = rewriteResult.rewrittenText
                    finalText = rewriteResult.rewrittenText
                    lastLatency = result.latency + rewriteResult.latency
                } catch {
                    // Fallback to raw transcription on rewrite failure
                    lastRewrite = ""
                    lastLatency = result.latency
                }
            } else {
                lastRewrite = ""
                lastLatency = result.latency
            }

            status = .pasting
            log.info("finalText to paste: '\(finalText)'")

            if source == .systemAudio {
                // System audio mode: copy to clipboard only (no paste into app)
                ClipboardWriter.write(finalText)
                log.info("System audio transcription copied to clipboard")
            } else {
                // Microphone mode: paste into the target app
                // Always re-activate the target app before pasting. Even though
                // WhisperFly is .accessory with a non-activating panel, the menu bar
                // popover or other apps can steal focus during transcription/rewrite.
                if let app = targetApp, !app.isTerminated {
                    let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
                    log.info("Target PID=\(app.processIdentifier), frontmost PID=\(frontPID ?? -1)")
                    app.activate()
                    // Wait for activation to settle — 200ms minimum.
                    try? await Task.sleep(for: .milliseconds(200))
                    // Verify activation succeeded; retry once if needed.
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                        log.warning("First activate() didn't take, retrying...")
                        app.activate()
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                } else {
                    log.warning("No valid targetApp, pasting to whatever is frontmost")
                    try? await Task.sleep(for: .milliseconds(settings.pasteDelayMs))
                }
                let targetPID = targetApp?.processIdentifier
                let insertResult: InsertResult
                do {
                    insertResult = try pasteService.insert(text: finalText, targetPID: targetPID)
                    log.info("Insert result: \(String(describing: insertResult))")
                } catch {
                    log.error("insert() threw: \(error.localizedDescription), trying clipboardInsert")
                    try? pasteService.clipboardInsert(finalText, targetPID: targetPID)
                }
            }

            if settings.readAloudEnabled {
                readAloud(finalText)
            }

            // Save to history
            let historySource: TranscriptionEntry.Source = source == .systemAudio ? .systemAudio : .microphone
            let entry = TranscriptionEntry(text: finalText, source: historySource, latency: lastLatency)
            history.add(entry)

            // Show result window only for system audio (mic just types into field)
            if source == .systemAudio {
                resultPanel.show(text: finalText, source: .systemAudio)
            }

            status = .idle
            targetApp = nil
            scheduleHidePanel()

        } catch {
            status = .error(error.localizedDescription)
            targetApp = nil
            floatingPanel.hide()
        }
    }

    private func readAloud(_ text: String) {
        speechSynthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: settings.sourceLanguage)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechSynthesizer.speak(utterance)
    }

    private func scheduleHidePanel() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            floatingPanel.hide()
        }
    }

    private func makeRecognizer() -> SpeechRecognizer {
        switch settings.transcriptionBackend {
        case .groqWhisper:
            return GroqWhisperRecognizer(apiKey: settings.groqApiKey, language: settings.sourceLanguage)
        case .gemini:
            return GeminiTranscriber(apiKey: settings.openRouterApiKey, language: settings.sourceLanguage, model: settings.openRouterModel)
        }
    }

    // MARK: - File Transcription

    /// Opens a file picker for audio/video files, transcribes the selected file,
    /// and copies the result to the clipboard.
    func transcribeFile() {
        guard status == .idle else { return }

        let panel = NSOpenPanel()
        panel.title = L("file.pick_title", "Select Audio or Video File")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = Self.mediaContentTypes

        guard panel.runModal() == .OK, let fileURL = panel.url else { return }

        currentFileName = fileURL.lastPathComponent
        status = .transcribing
        errorMessage = nil
        hideTask?.cancel()
        floatingPanel.show(with: self)

        Task {
            await processFile(url: fileURL)
        }
    }

    private static let mediaContentTypes: [UTType] = {
        var types: [UTType] = [.audio, .movie]
        if let mp3 = UTType(filenameExtension: "mp3") { types.append(mp3) }
        if let m4a = UTType(filenameExtension: "m4a") { types.append(m4a) }
        if let wav = UTType(filenameExtension: "wav") { types.append(wav) }
        if let flac = UTType(filenameExtension: "flac") { types.append(flac) }
        return types
    }()

    /// Extracts audio from the file (if needed), transcribes, optionally rewrites,
    /// and copies the final text to the clipboard.
    private func processFile(url: URL) async {
        var extractedURL: URL?
        defer {
            if let extracted = extractedURL, extracted != url {
                try? FileManager.default.removeItem(at: extracted)
            }
        }

        do {
            let audioURL = try await AudioConverter.extractAudio(from: url)
            extractedURL = audioURL

            let recognizer = makeRecognizer()
            let result = try await recognizer.transcribe(audioURL: audioURL)
            lastTranscription = result.text

            guard !result.text.isEmpty else {
                status = .error(L("error.no_speech", "No speech detected"))
                floatingPanel.hide()
                return
            }

            var finalText = result.text

            if settings.geminiRewriteEnabled, !settings.openRouterApiKey.isEmpty {
                status = .rewriting
                do {
                    let rewriter = GeminiRewriter(apiKey: settings.openRouterApiKey, model: settings.openRouterModel)
                    let rewriteResult = try await rewriter.rewrite(
                        inputText: result.text,
                        locale: Locale.current,
                        mode: settings.rewriteMode
                    )
                    lastRewrite = rewriteResult.rewrittenText
                    finalText = rewriteResult.rewrittenText
                    lastLatency = result.latency + rewriteResult.latency
                } catch {
                    lastRewrite = ""
                    lastLatency = result.latency
                }
            } else {
                lastRewrite = ""
                lastLatency = result.latency
            }

            // Always copy to clipboard for file transcription
            status = .pasting
            ClipboardWriter.write(finalText)
            log.info("File transcription copied to clipboard (\(finalText.count) chars)")

            if settings.readAloudEnabled {
                readAloud(finalText)
            }

            // Save to history
            let fName = currentFileName
            let entry = TranscriptionEntry(text: finalText, source: .file, fileName: fName, latency: lastLatency)
            history.add(entry)
            currentFileName = nil

            // Show result window
            resultPanel.show(text: finalText, source: .file, fileName: fName)

            status = .idle
            scheduleHidePanel()

        } catch {
            currentFileName = nil
            status = .error(error.localizedDescription)
            floatingPanel.hide()
        }
    }

    // MARK: - Settings

    func saveSettings() {
        settingsStore.save(settings)
        pasteService = PasteService(pasteDelayMs: settings.pasteDelayMs)
        audioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
        systemAudioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
        syncUpdateConfiguration()
        reregisterHotkeyIfNeeded()
    }

    /// Keeps the updater pointed at the repository the settings UI names.
    private func syncUpdateConfiguration() {
        let configuration = Self.updateConfiguration(from: settings)
        if updates.configuration != configuration {
            updates.configuration = configuration
        }
    }

    // MARK: - Permissions and updates (UI entry points)

    /// Clears this app's TCC rows and relaunches.
    ///
    /// This is the only reliable remedy when the build was re-signed: macOS keeps
    /// the old grant rows matched to a designated requirement that no longer
    /// applies, so System Settings shows WhisperFly as enabled while the running
    /// process is still untrusted. Toggling cannot fix that — the row has to go.
    @discardableResult
    func repairPermissionsAndRelaunch() -> String? {
        let failures = PermissionRepair.resetAll(bundleIdentifier: BuildInfo.bundleIdentifier)
        guard failures.isEmpty else {
            // Deliberately do not relaunch: restarting on a half-cleared state
            // would drop the user back into the same broken app with no reason.
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
                    body: L("permission.relaunch_hint",
                            "Granted. WhisperFly needs to restart before this takes effect.")
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

    func dismissError() {
        status = .idle
        errorMessage = nil
    }

    var hasValidAPIKeys: Bool {
        switch settings.transcriptionBackend {
        case .groqWhisper:
            return !settings.groqApiKey.isEmpty
        case .gemini:
            return !settings.openRouterApiKey.isEmpty
        }
    }
}
