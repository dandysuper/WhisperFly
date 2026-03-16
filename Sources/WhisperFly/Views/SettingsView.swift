import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            apiTab
                .tabItem { Label("API Keys", systemImage: "key") }
            advancedTab
                .tabItem { Label("Advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 480, height: 380)
    }
    
    private var generalTab: some View {
        Form {
            Picker("Transcription Backend", selection: $controller.settings.transcriptionBackend) {
                ForEach(AppSettings.TranscriptionBackend.allCases, id: \.self) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            
            Picker("Source Language", selection: $controller.settings.sourceLanguage) {
                Text("Russian").tag("ru")
                Text("English").tag("en")
                Text("German").tag("de")
                Text("French").tag("fr")
                Text("Spanish").tag("es")
                Text("Japanese").tag("ja")
                Text("Chinese").tag("zh")
                Text("Korean").tag("ko")
                Text("Italian").tag("it")
                Text("Hindi").tag("hi")
            }
            
            Toggle("Enable Gemini Rewriting", isOn: $controller.settings.geminiRewriteEnabled)
            
            if controller.settings.geminiRewriteEnabled {
                Picker("Rewrite Mode", selection: $controller.settings.rewriteMode) {
                    ForEach(RewriteMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }
            
            Picker("Hotkey", selection: $controller.settings.hotkey) {
                ForEach(AppSettings.HotkeyPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
        }
        .onChange(of: controller.settings) { _, _ in
            controller.saveSettings()
        }
    }
    
    private var apiTab: some View {
        Form {
            Section("Groq (Whisper ASR)") {
                SecureField("API Key", text: $controller.settings.groqApiKey)
                    .textFieldStyle(.roundedBorder)
                if controller.settings.groqApiKey.isEmpty {
                    Text("Get free key at console.groq.com")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("Key configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Section("OpenRouter (Gemini Flash)") {
                SecureField("API Key", text: $controller.settings.openRouterApiKey)
                    .textFieldStyle(.roundedBorder)
                if controller.settings.openRouterApiKey.isEmpty {
                    Text("Get free key at openrouter.ai")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("Key configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .onChange(of: controller.settings) { _, _ in
            controller.saveSettings()
        }
    }
    
    private var advancedTab: some View {
        Form {
            Stepper("Max Recording: \(controller.settings.maxRecordingSeconds)s",
                    value: $controller.settings.maxRecordingSeconds,
                    in: 10...300, step: 10)
            
            Stepper("Paste Delay: \(controller.settings.pasteDelayMs)ms",
                    value: $controller.settings.pasteDelayMs,
                    in: 50...500, step: 25)
        }
        .onChange(of: controller.settings) { _, _ in
            controller.saveSettings()
        }
    }
}
