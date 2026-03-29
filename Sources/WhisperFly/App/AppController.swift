import Foundation
import SwiftUI
import AVFoundation
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
    private var hotkeyMonitor = HotkeyMonitor()
    private var pasteService: PasteService
    private var currentRecordingURL: URL?
    private let floatingPanel = FloatingPanel()
    private var hideTask: Task<Void, Never>?
    private let speechSynthesizer = AVSpeechSynthesizer()
    private var targetApp: NSRunningApplication?
    private var accessibilityPollTask: Task<Void, Never>?
    
    @Published var accessibilityGranted: Bool = false

    init() {
        let loaded = SettingsStore().load()
        self.settings = loaded
        self.pasteService = PasteService(pasteDelayMs: loaded.pasteDelayMs)

        setupAudioCallbacks()
        setupHotkey()
        checkAccessibilityPermission()
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
        targetApp = NSWorkspace.shared.frontmostApplication
        status = .recording
        errorMessage = nil
        hideTask?.cancel()
        floatingPanel.show(with: self)
        
        Task {
            do {
                let url = try await audioService.startRecording()
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
                let url = try await audioService.stopRecording()
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

            if settings.readAloudEnabled {
                readAloud(finalText)
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
    
    // MARK: - Settings
    
    func saveSettings() {
        settingsStore.save(settings)
        pasteService = PasteService(pasteDelayMs: settings.pasteDelayMs)
        audioService.configure(maxRecordingSeconds: settings.maxRecordingSeconds)
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
