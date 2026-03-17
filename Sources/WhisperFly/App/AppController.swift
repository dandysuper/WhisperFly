import Foundation
import SwiftUI
import AVFoundation

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
    
    init() {
        let loaded = SettingsStore().load()
        self.settings = loaded
        self.pasteService = PasteService(pasteDelayMs: loaded.pasteDelayMs)
        
        setupAudioCallbacks()
        setupHotkey()
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
        floatingPanel.hide()
    }
    
    // MARK: - Transcription + Rewrite Pipeline
    
    private func processAudio(url: URL) async {
        status = .transcribing
        audioLevel = -160
        
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
                    let rewriter = GeminiRewriter(apiKey: settings.openRouterApiKey)
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
            do {
                let _ = try pasteService.insert(text: finalText)
            } catch {
                // Copy to clipboard as last resort
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(finalText, forType: .string)
            }
            
            if settings.readAloudEnabled {
                readAloud(finalText)
            }
            
            status = .idle
            scheduleHidePanel()
            
        } catch {
            status = .error(error.localizedDescription)
            floatingPanel.hide()
        }
        
        // Cleanup recording file
        try? FileManager.default.removeItem(at: url)
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
            return GeminiTranscriber(apiKey: settings.openRouterApiKey, language: settings.sourceLanguage)
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
