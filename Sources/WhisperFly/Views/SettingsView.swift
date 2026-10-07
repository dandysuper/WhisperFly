import SwiftUI

struct SettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(L("settings.tab.general", "General"), systemImage: "gear") }
            apiTab
                .tabItem { Label(L("settings.tab.api_keys", "API Keys"), systemImage: "key") }
            PermissionsView(controller: controller, permissions: controller.permissions)
                .tabItem { Label(L("settings.tab.permissions", "Permissions"), systemImage: "lock.shield") }
            UpdatesView(controller: controller, updates: controller.updates)
                .tabItem { Label(L("settings.tab.updates", "Updates"), systemImage: "arrow.down.circle") }
            advancedTab
                .tabItem { Label(L("settings.tab.advanced", "Advanced"), systemImage: "slider.horizontal.3") }
        }
        .padding(20)
        .frame(width: 520, height: 470)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Picker(L("settings.audio_source", "Audio Source"),
                   selection: $controller.settings.audioSource) {
                ForEach(AppSettings.AudioSource.allCases) { source in
                    Label(source.localizedName, systemImage: source.systemImage).tag(source)
                }
            }

            Picker(L("settings.transcription_backend", "Transcription Backend"),
                   selection: $controller.settings.transcriptionBackend) {
                ForEach(AppSettings.TranscriptionBackend.allCases) { backend in
                    Text(backend.displayName).tag(backend)
                }
            }

            Picker(L("settings.source_language", "Source Language"),
                   selection: $controller.settings.sourceLanguage) {
                Text(L("lang.en", "English")).tag("en")
                Text(L("lang.ru", "Russian")).tag("ru")
                Text(L("lang.de", "German")).tag("de")
                Text(L("lang.fr", "French")).tag("fr")
                Text(L("lang.es", "Spanish")).tag("es")
                Text(L("lang.ja", "Japanese")).tag("ja")
                Text(L("lang.zh", "Chinese")).tag("zh")
                Text(L("lang.ko", "Korean")).tag("ko")
                Text(L("lang.it", "Italian")).tag("it")
                Text(L("lang.hi", "Hindi")).tag("hi")
            }

            Toggle(L("settings.enable_rewriting", "Enable Gemini Rewriting"),
                   isOn: $controller.settings.geminiRewriteEnabled)

            if controller.settings.geminiRewriteEnabled {
                Picker(L("settings.rewrite_mode", "Rewrite Mode"),
                       selection: $controller.settings.rewriteMode) {
                    ForEach(RewriteMode.allCases, id: \.self) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
            }

            Picker(L("settings.hotkey", "Global Shortcut"),
                   selection: $controller.settings.hotkey) {
                ForEach(AppSettings.HotkeyPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }

            if let error = controller.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(L("settings.read_aloud", "Read Aloud After Pasting"),
                   isOn: $controller.settings.readAloudEnabled)
        }
        .onChange(of: controller.settings) { _, _ in controller.saveSettings() }
    }

    // MARK: - API keys

    private var apiTab: some View {
        Form {
            Section(L("settings.groq_section", "Groq (Whisper ASR)")) {
                SecureField(L("settings.api_key", "API Key"), text: $controller.settings.groqApiKey)
                    .textFieldStyle(.roundedBorder)
                if controller.settings.groqApiKey.isEmpty {
                    Text(L("settings.groq_hint", "Get a free key at console.groq.com"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label(L("settings.key_configured", "Key configured"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Section(L("settings.openrouter_section", "OpenRouter (Gemini Flash)")) {
                SecureField(L("settings.api_key", "API Key"), text: $controller.settings.openRouterApiKey)
                    .textFieldStyle(.roundedBorder)
                if controller.settings.openRouterApiKey.isEmpty {
                    Text(L("settings.openrouter_hint", "Get a free key at openrouter.ai"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label(L("settings.key_configured", "Key configured"), systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .onChange(of: controller.settings) { _, _ in controller.saveSettings() }
    }

    // MARK: - Advanced

    private var advancedTab: some View {
        Form {
            Stepper(
                L("settings.max_recording", "Max Recording: %ds", controller.settings.maxRecordingSeconds),
                value: $controller.settings.maxRecordingSeconds,
                in: 10...300, step: 10
            )

            Stepper(
                L("settings.paste_delay", "Paste Delay: %dms", controller.settings.pasteDelayMs),
                value: $controller.settings.pasteDelayMs,
                in: 50...500, step: 25
            )

            Section(L("settings.openrouter_model_section", "OpenRouter Model")) {
                TextField(L("settings.openrouter_model", "Model ID"),
                          text: $controller.settings.openRouterModel)
                    .textFieldStyle(.roundedBorder)
                Text(L("settings.openrouter_model_hint", "Default: google/gemini-2.5-flash"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onChange(of: controller.settings) { _, _ in controller.saveSettings() }
    }
}
