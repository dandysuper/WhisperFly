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
    private var accessibilityPollTask: Task<Void, Never>?
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

    @Published var accessibilityGranted: Bool = false
    @Published var screenRecordingGranted: Bool = false

    init() {
        let loaded = SettingsStore().load()
        self.settings = loaded
        self.pasteService = PasteService(pasteDelayMs: loaded.pasteDelayMs)

        setupAudioCallbacks()
        setupHotkey()
        checkAccessibilityPermission()
        checkScreenRecordingPermission()
        observeAppActivation()
        requestNotificationAuthorization()
    }

    /// Re-checks accessibility whenever the app becomes active (e.g. user returns from System Settings).
    private func observeAppActivation() {
        requestNotificationAuthorization()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.accessibilityGranted = Self.probeAccessibility()
                self.checkScreenRecordingPermission()
            }
        }
    }

    /// Actually attempts an AX call to verify accessibility works (not just cached).
    /// `AXIsProcessTrusted()` can return a stale `true` after the binary changes,
    /// so we do a real probe: query the system-wide focused element.
    private static func probeAccessibility() -> Bool {
        PasteService.isAccessibilityWorking()
    }

    /// Checks Accessibility permission; starts a background poll until granted.
    func checkAccessibilityPermission() {
        // Show the system prompt if not trusted at all.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Use the live probe, not the cached API.
        accessibilityGranted = Self.probeAccessibility()
        guard !accessibilityGranted else { return }

        // Cancel any existing poll and start a new one (no timeout — polls until granted).
        accessibilityPollTask?.cancel()
        accessibilityPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Self.probeAccessibility() {
                    await MainActor.run {
                        self.accessibilityGranted = true
                        self.accessibilityPollTask = nil
                    }
                    return
                }
            }
        }
    }

    /// Lightweight re-check without showing the system prompt.
    /// Call this whenever the UI becomes visible (e.g. menu popover opens).
    func refreshAccessibility() {
        accessibilityGranted = Self.probeAccessibility()
    }

    // MARK: - Screen Recording Permission

    /// Checks whether Screen Recording permission is likely granted.
    func checkScreenRecordingPermission() {
        screenRecordingGranted = Self.probeScreenRecording()
    }

    /// Probes Screen Recording permission by attempting a lightweight SCShareableContent query.
    /// On macOS 14+, SCShareableContent throws if not authorized.
    private static func probeScreenRecording() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Opens System Settings to the Screen Recording pane.
    func requestScreenRecordingPermission() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
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
        do {
            try hotkeyMonitor.register()
        } catch {
            self.errorMessage = "Hotkey registration failed: \(error.localizedDescription)"
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
        refreshAccessibility()

        switch settings.audioSource {
        case .microphone:
            let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            switch authStatus {
            case .denied, .restricted:
                status = .error("Microphone access denied. Open System Settings -> Privacy -> Microphone.")
                showNotification(title: "Microphone Required", body: "Open System Settings -> Privacy -> Microphone and enable WhisperFly.")
                return
            default:
                break
            }

        case .systemAudio:
            CGRequestScreenCaptureAccess()
            checkScreenRecordingPermission()
            if !screenRecordingGranted {
                if #available(macOS 26, *) {
                    // CGPreflightScreenCaptureAccess() has known false negatives
                    // on macOS 26 (Tahoe). Defer to the SCShareableContent call
                    // inside SystemAudioCaptureService as the authoritative check.
                    log.warning("CGPreflightScreenCaptureAccess returned false — proceeding anyway (macOS 26 false-negative workaround)")
                } else {
                    // On macOS 14/15, CGPreflightScreenCaptureAccess() is reliable.
                    status = .error("Screen Recording permission required for system audio capture.")
                    showNotification(
                        title: "Screen Recording Required",
                        body: "Open System Settings → Privacy & Security → Screen Recording and enable WhisperFly, then try again."
                    )
                    requestScreenRecordingPermission()
                    return
                }
            }
        }

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
                await processAudio(url: url)
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

    private func processAudio(url: URL) async {
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

            if settings.audioSource == .systemAudio {
                // System audio mode: copy to clipboard only (no paste into app)
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(finalText, forType: .string)
                log.info("✅ System audio transcription copied to clipboard")
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
            let historySource: TranscriptionEntry.Source = settings.audioSource == .systemAudio ? .systemAudio : .microphone
            let entry = TranscriptionEntry(text: finalText, source: historySource, latency: lastLatency)
            history.add(entry)

            // Show result window only for system audio (mic just types into field)
            if settings.audioSource == .systemAudio {
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
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(finalText, forType: .string)
            log.info("✅ File transcription copied to clipboard (\(finalText.count) chars)")

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
