import SwiftUI

/// The optional AI pass: mode, engine, translation target, custom
/// instructions, and the vocabulary shared with the speech engine.
struct RewritingSettingsView: View {
    @ObservedObject var controller: AppController

    private var provider: AIProvider { controller.settings.rewriteProvider }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $controller.settings.rewriteEnabled) {
                    Text(L("settings.rewrite_enabled", "Rewrite transcripts with AI"))
                    Text(L("settings.rewrite_enabled.hint", "Runs after transcription. If it fails, the original transcript is used."))
                }
            }

            if controller.settings.rewriteEnabled {
                Section(L("settings.rewrite_mode", "Mode")) {
                    modeGrid
                        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))

                    if controller.settings.rewriteMode == .translate {
                        Picker(L("settings.target_language", "Translate into"), selection: $controller.settings.targetLanguage) {
                            ForEach(DictationLanguage.translationTargets) { language in
                                Text(language.localizedName).tag(language.code)
                            }
                        }
                    }

                    if controller.settings.rewriteMode == .custom {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("settings.custom_prompt", "Instructions"))
                                .font(.system(size: 12, weight: .medium))
                            TextEditor(text: $controller.settings.customSystemPrompt)
                                .font(.system(size: 12))
                                .frame(minHeight: 90)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                            Text(L("settings.custom_prompt.hint", "For example: “Write in British English, use short sentences, and format action items as a checklist.”"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if controller.settings.rewriteMode == .cleanup
                        && controller.settings.transcriptionProvider == .gemini
                        && controller.settings.geminiSmartTranscription {
                        Label(L("settings.cleanup_skipped", "Gemini smart transcription already cleans up dictation, so this pass is skipped."), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L("settings.rewrite_engine", "Engine")) {
                    Picker(L("settings.provider", "Provider"), selection: $controller.settings.rewriteProvider) {
                        ForEach(AIProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }

                    ModelField(title: L("settings.model", "Model"), model: rewriteModelBinding, options: provider.rewriteModels)

                    if !controller.settings.isConfigured(provider) {
                        HStack {
                            Label(L("settings.rewrite_no_key", "%@ has no API key, so rewriting is skipped.", provider.shortName), systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                            Button(L("action.add_key", "Add Key")) { controller.navigation.selection = .providers }
                                .controlSize(.small)
                        }
                    }
                }
            }

            Section {
                TextEditor(text: $controller.settings.customVocabulary)
                    .font(.system(size: 12))
                    .frame(minHeight: 70)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            } header: {
                Text(L("settings.vocabulary", "Custom Vocabulary"))
            } footer: {
                Text(L("settings.vocabulary.hint", "Names, product terms and acronyms, separated by commas or new lines — e.g. “Kubernetes, WhisperFly, Daniyar”. Sent to the speech engine as hints and to the rewriter as spellings to keep."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var modeGrid: some View {
        GlassGroup(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(RewriteMode.allCases) { mode in
                    modeCard(mode)
                }
            }
        }
    }

    private func modeCard(_ mode: RewriteMode) -> some View {
        let isSelected = controller.settings.rewriteMode == mode
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { controller.settings.rewriteMode = mode }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.purple : Color.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.localizedName)
                        .font(.system(size: 13, weight: .semibold))
                    Text(mode.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(
            RoundedRectangle(cornerRadius: 14, style: .continuous),
            tint: isSelected ? Color.purple.opacity(0.22) : nil,
            interactive: true
        )
    }

    private var rewriteModelBinding: Binding<String> {
        Binding(
            get: {
                switch provider {
                case .groq:       return controller.settings.groqRewriteModel
                case .gemini:     return controller.settings.geminiRewriteModel
                case .openRouter: return controller.settings.openRouterModel
                case .custom:     return controller.settings.customRewriteModel
                }
            },
            set: { value in
                switch provider {
                case .groq:       controller.settings.groqRewriteModel = value
                case .gemini:     controller.settings.geminiRewriteModel = value
                case .openRouter: controller.settings.openRouterModel = value
                case .custom:     controller.settings.customRewriteModel = value
                }
            }
        )
    }
}
