import SwiftUI

/// Result of a key check, per provider.
enum KeyCheckState: Equatable {
    case idle
    case checking
    case valid
    case failed(String)
}

/// Speech engine choice, models, and every provider's credentials.
struct ProvidersSettingsView: View {
    @ObservedObject var controller: AppController
    @StateObject private var checks = LocalState<[AIProvider: KeyCheckState]>([:])

    private var selected: AIProvider { controller.settings.transcriptionProvider }

    var body: some View {
        Form {
            Section {
                ProviderPicker(selection: $controller.settings.transcriptionProvider, settings: controller.settings)
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))

                ModelField(
                    title: L("settings.model", "Model"),
                    model: transcriptionModelBinding,
                    options: selected.transcriptionModels
                )

                if selected == .gemini && controller.settings.geminiTranscriptionModel.contains("transcribe") {
                    Toggle(isOn: $controller.settings.geminiSmartTranscription) {
                        Text(L("settings.gemini_smart", "Smart transcription"))
                        Text(L("settings.gemini_smart.hint", "Gemini removes filler words, applies your spoken corrections and formats lists, numbers and dates. AI Cleanup is skipped when this is on."))
                    }
                }

                Toggle(isOn: $controller.settings.fallbackEnabled) {
                    Text(L("settings.fallback", "Fall back to another engine"))
                    Text(L("settings.fallback.hint", "If the selected engine fails or hits its free-tier limit, try the next one you have a key for."))
                }
            } header: {
                Text(L("settings.transcription_engine", "Transcription Engine"))
            }

            Section {
                ForEach([AIProvider.groq, .gemini, .openRouter]) { provider in
                    keyRow(provider)
                }
            } header: {
                Text(L("settings.api_keys", "API Keys"))
            } footer: {
                Text(L("settings.api_keys.footer", "Keys are stored in WhisperFly's preferences on this Mac and sent only to their own provider. One free Groq key covers both transcription and AI rewriting."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField(L("settings.custom.base_url", "Base URL"), text: $controller.settings.customBaseURL, prompt: Text("https://api.openai.com/v1"))
                SecureField(L("settings.api_key", "API Key"), text: $controller.settings.customApiKey, prompt: Text(L("settings.custom.key_prompt", "Optional for local servers")))
                ModelField(
                    title: L("settings.custom.transcription_model", "Transcription model"),
                    model: $controller.settings.customTranscriptionModel,
                    options: AIProvider.custom.transcriptionModels
                )
                ModelField(
                    title: L("settings.custom.rewrite_model", "Rewrite model"),
                    model: $controller.settings.customRewriteModel,
                    options: AIProvider.custom.rewriteModels
                )
                HStack {
                    Spacer()
                    verifyButton(.custom)
                }
            } header: {
                Text(L("settings.custom.header", "OpenAI-Compatible Server"))
            } footer: {
                Text(L("settings.custom.footer", "Works with OpenAI, whisper.cpp's server, LocalAI, faster-whisper servers and other APIs that offer /audio/transcriptions and /chat/completions."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Key rows

    private func keyRow(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SettingsIcon(systemImage: provider.systemImage, tint: provider.tint, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(provider.displayName).font(.system(size: 13, weight: .semibold))
                        if provider.isFree { Chip(text: L("settings.free", "Free"), tint: .green) }
                    }
                    Text(provider.tagline)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let url = provider.keyURL {
                    Link(destination: url) {
                        Label(L("settings.get_key", "Get Key"), systemImage: "arrow.up.right.square")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
            }
            HStack(spacing: 8) {
                SecureField("", text: keyBinding(provider), prompt: Text(provider.keyPlaceholder))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                verifyButton(provider)
            }
            checkStatus(provider)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func checkStatus(_ provider: AIProvider) -> some View {
        switch checks.value[provider] ?? .idle {
        case .idle:
            EmptyView()
        case .checking:
            EmptyView()
        case .valid:
            Label(L("settings.key_valid", "Key works"), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func verifyButton(_ provider: AIProvider) -> some View {
        Button {
            verify(provider)
        } label: {
            if checks.value[provider] == .checking {
                ProgressView().controlSize(.small)
            } else {
                Text(L("settings.verify", "Verify"))
            }
        }
        .glassButton()
        .disabled(checks.value[provider] == .checking || (!controller.settings.isConfigured(provider) && provider != .custom))
    }

    private func verify(_ provider: AIProvider) {
        checks.value[provider] = .checking
        let settings = controller.settings
        Task {
            do {
                try await ProviderKeyValidator.validate(provider, settings: settings)
                checks.value[provider] = .valid
            } catch {
                checks.value[provider] = .failed(error.localizedDescription)
            }
        }
    }

    private func keyBinding(_ provider: AIProvider) -> Binding<String> {
        Binding(
            get: { rawKey(provider) },
            set: { newValue in
                checks.value[provider] = .idle
                switch provider {
                case .groq:       controller.settings.groqApiKey = newValue
                case .gemini:     controller.settings.geminiApiKey = newValue
                case .openRouter: controller.settings.openRouterApiKey = newValue
                case .custom:     controller.settings.customApiKey = newValue
                }
            }
        )
    }

    private func rawKey(_ provider: AIProvider) -> String {
        switch provider {
        case .groq:       return controller.settings.groqApiKey
        case .gemini:     return controller.settings.geminiApiKey
        case .openRouter: return controller.settings.openRouterApiKey
        case .custom:     return controller.settings.customApiKey
        }
    }

    private var transcriptionModelBinding: Binding<String> {
        Binding(
            get: {
                switch selected {
                case .groq:       return controller.settings.groqTranscriptionModel
                case .gemini:     return controller.settings.geminiTranscriptionModel
                case .openRouter: return controller.settings.openRouterModel
                case .custom:     return controller.settings.customTranscriptionModel
                }
            },
            set: { value in
                switch selected {
                case .groq:       controller.settings.groqTranscriptionModel = value
                case .gemini:     controller.settings.geminiTranscriptionModel = value
                case .openRouter: controller.settings.openRouterModel = value
                case .custom:     controller.settings.customTranscriptionModel = value
                }
            }
        )
    }
}

/// Four glass cards, one per provider.
struct ProviderPicker: View {
    @Binding var selection: AIProvider
    let settings: AppSettings
    var providers: [AIProvider] = AIProvider.allCases

    var body: some View {
        GlassGroup(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(providers) { provider in
                    card(provider)
                }
            }
        }
    }

    private func card(_ provider: AIProvider) -> some View {
        let isSelected = selection == provider
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = provider }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                SettingsIcon(systemImage: provider.systemImage, tint: provider.tint, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(provider.displayName)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        if provider.isFree { Chip(text: L("settings.free", "Free"), tint: .green) }
                    }
                    Text(provider.tagline)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !settings.isConfigured(provider) {
                        Text(L("settings.no_key", "No key yet"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? provider.tint : Color.secondary.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(
            RoundedRectangle(cornerRadius: 16, style: .continuous),
            tint: isSelected ? provider.tint.opacity(0.22) : nil,
            interactive: true
        )
    }
}

/// A model-ID text field with a menu of suggestions.
struct ModelField: View {
    let title: String
    @Binding var model: String
    let options: [ModelOption]

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minWidth: 200)
                if !options.isEmpty {
                    Menu {
                        ForEach(options) { option in
                            Button {
                                model = option.id
                            } label: {
                                if option.id == model {
                                    Label("\(option.id) — \(option.note)", systemImage: "checkmark")
                                } else {
                                    Text("\(option.id) — \(option.note)")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(L("settings.model_suggestions", "Suggested models"))
                }
            }
        }
    }
}
