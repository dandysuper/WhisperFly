import Foundation
import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import os.log

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
    }

    /// Re-checks accessibility whenever the app becomes active (e.g. user returns from System Settings).
    private func observeAppActivation() {
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
        // CGWindowListCopyWindowInfo returns empty or a nil array when Screen Recording is denied.
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        // If we get window info with owner names from other apps, permission is granted.
        let hasOtherAppWindows = list.contains { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32 else { return false }
            return pid != ProcessInfo.processInfo.processIdentifier
        }
        return hasOtherAppWindows
    }

    /// Opens System Settings to the Screen Recording pane.
    func requestScreenRecordingPermission() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
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
                self?.audioLevel = level
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
        // Only capture target app for microphone mode (paste into it)
        if settings.audioSource == .microphone {
            targetApp = NSWorkspace.shared.frontmostApplication
        } else {
            targetApp = nil
        }
        status = .recording
        errorMessage = nil
        hideTask?.cancel()
        floatingPanel.show(with: self)
        
        Task {
            do {
                let url: URL
                switch settings.audioSource {
                case .microphone:
                    url = try await audioService.startRecording()
                case .systemAudio:
                    url = try await systemAudioService.startRecording()
                }
                currentRecordingURL = url
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }
    
    func finishRecording() {
        guard status == .recording else { return }
        
        Task {
            do {
                let url: URL
                switch settings.audioSource {
                case .microphone:
                    url = try await audioService.stopRecording()
                case .systemAudio:
                    url = try await systemAudioService.stopRecording()
                }
                currentRecordingURL = url
                await processAudio(url: url)
            } catch {
                status = .error(error.localizedDescription)
            }
        }
    }
    
    func cancelCurrentOperation() {
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
