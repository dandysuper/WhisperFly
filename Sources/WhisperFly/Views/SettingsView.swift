import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController
    
    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("settings.tab.general", systemImage: "gear") }
            apiTab
                .tabItem { Label("settings.tab.api_keys", systemImage: "key") }
            advancedTab
                .tabItem { Label("settings.tab.advanced", systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 480, height: 400)
    }
    
    private var generalTab: some View {
        Form {
            Picker("settings.transcription_backend", selection: $controller.settings.transcriptionBackend) {
                ForEach(AppSettings.TranscriptionBackend.allCases, id: \.self) { backend in
                    Text(backend.rawValue).tag(backend)
                }
            }
            
            Picker("settings.source_language", selection: $controller.settings.sourceLanguage) {
                Text("lang.ru").tag("ru")
                Text("lang.en").tag("en")
                Text("lang.de").tag("de")
                Text("lang.fr").tag("fr")
                Text("lang.es").tag("es")
                Text("lang.ja").tag("ja")
                Text("lang.zh").tag("zh")
                Text("lang.ko").tag("ko")
                Text("lang.it").tag("it")
                Text("lang.hi").tag("hi")
            }
            
            Toggle("settings.enable_rewriting", isOn: $controller.settings.geminiRewriteEnabled)
            
            if controller.settings.geminiRewriteEnabled {
                Picker("settings.rewrite_mode", selection: $controller.settings.rewriteMode) {
                    ForEach(RewriteMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
            }
            
            Picker("settings.hotkey", selection: $controller.settings.hotkey) {
                ForEach(AppSettings.HotkeyPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            
            Toggle("settings.read_aloud", isOn: $controller.settings.readAloudEnabled)
        }
        .onChange(of: controller.settings) { _, _ in
            controller.saveSettings()
        }
    }
    
    private var apiTab: some View {
        Form {
            Section(String(localized: "settings.groq_section", defaultValue: "Groq (Whisper ASR)")) {
                SecureField("settings.api_key", text: $controller.settings.groqApiKey)
                    .textFieldStyle(.roundedBorder)
                if controller.settings.groqApiKey.isEmpty {
                    Text("settings.groq_hint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("settings.key_configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            
            Section(String(localized: "settings.openrouter_section", defaultValue: "OpenRouter (Gemini Flash)")) {
                SecureField("settings.api_key", text: $controller.settings.openRouterApiKey)
                    .textFieldStyle(.roundedBorder)
                if controller.settings.openRouterApiKey.isEmpty {
                    Text("settings.openrouter_hint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("settings.key_configured", systemImage: "checkmark.circle.fill")
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
            Stepper(
                String(format: NSLocalizedString("settings.max_recording", value: "Max Recording: %ds", comment: ""), controller.settings.maxRecordingSeconds),
                value: $controller.settings.maxRecordingSeconds,
                in: 10...300, step: 10
            )
            
            Stepper(
                String(format: NSLocalizedString("settings.paste_delay", value: "Paste Delay: %dms", comment: ""), controller.settings.pasteDelayMs),
                value: $controller.settings.pasteDelayMs,
                in: 50...500, step: 25
            )
        }
        .onChange(of: controller.settings) { _, _ in
            controller.saveSettings()
        }
    }
}
