import SwiftUI

/// The settings window: a Liquid Glass sidebar of sections and a grouped form
/// for each. Every control binds straight to `controller.settings`, which
/// persists itself on change.
struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $navigation.selection) { section in
                Label {
                    Text(section.title)
                } icon: {
                    SettingsIcon(systemImage: section.systemImage, tint: section.tint)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 260)
        } detail: {
            let section = navigation.selection ?? .general
            detail(for: section)
                .navigationTitle(section.title)
        }
    }

    @ViewBuilder
    private func detail(for section: SettingsSection) -> some View {
        switch section {
        case .general:     GeneralSettingsView(controller: controller)
        case .providers:   ProvidersSettingsView(controller: controller)
        case .rewriting:   RewritingSettingsView(controller: controller)
        case .permissions: PermissionsView(controller: controller, permissions: controller.permissions)
        case .updates:     UpdatesView(controller: controller, updates: controller.updates)
        case .advanced:    AdvancedSettingsView(controller: controller, history: controller.history)
        }
    }
}

/// System Settings–style rounded-square icon.
struct SettingsIcon: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).fill(tint.gradient))
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Section(L("settings.dictation", "Dictation")) {
                Picker(L("settings.audio_source", "Audio Source"), selection: $controller.settings.audioSource) {
                    ForEach(AppSettings.AudioSource.allCases) { source in
                        Label(source.localizedName, systemImage: source.systemImage).tag(source)
                    }
                }

                Picker(L("settings.source_language", "Spoken Language"), selection: $controller.settings.sourceLanguage) {
                    ForEach(DictationLanguage.all) { language in
                        Text(language.localizedName).tag(language.code)
                    }
                }

                LabeledContent(L("settings.hotkey", "Shortcut")) {
                    HStack(spacing: 10) {
                        KeyCaps(keys: controller.settings.hotkey.keyCaps)
                        Picker("", selection: $controller.settings.hotkey) {
                            ForEach(AppSettings.HotkeyPreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                }

                if controller.settings.hotkey.isFunctionKey {
                    Text(L("settings.fn.hint", "fn on its own always dictates from the microphone. WhisperFly needs Accessibility permission to see the key. Combinations like fn+Delete keep working. Built-in and Apple keyboards only — choose a key combination for other keyboards."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let conflict = controller.fnKeyConflict {
                        FnConflictNotice(conflict: conflict)
                    }
                }

                if let error = controller.hotkeyError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle(isOn: $controller.settings.holdToTalkEnabled) {
                    Text(L("settings.hold_to_talk", "Hold to talk"))
                    Text(L("settings.hold_to_talk.hint", "Hold the shortcut while speaking and release to transcribe. A quick tap still starts and stops recording."))
                }
            }

            Section(L("settings.output", "Output")) {
                Picker(selection: $controller.settings.insertionMethod) {
                    ForEach(AppSettings.InsertionMethod.allCases) { method in
                        Text(method.localizedName).tag(method)
                    }
                } label: {
                    Text(L("settings.insertion", "Insert text"))
                    Text(L("settings.insertion.hint", "Choose “Always paste” if text does not appear in apps like Slack, VS Code or some browsers."))
                }

                Toggle(L("settings.sounds", "Play start and stop sounds"), isOn: $controller.settings.soundEffectsEnabled)
                Toggle(L("settings.read_aloud", "Read result aloud"), isOn: $controller.settings.readAloudEnabled)
            }

            Section(L("settings.system", "System")) {
                Toggle(L("settings.launch_at_login", "Open at login"), isOn: Binding(
                    get: { controller.launchAtLogin },
                    set: { controller.launchAtLogin = $0 }
                ))
                .disabled(!BuildInfo.isAppBundle)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Advanced

struct AdvancedSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var history: TranscriptionHistory
    @StateObject private var confirmClear = LocalFlag(false)

    var body: some View {
        Form {
            Section(L("settings.capture", "Capture")) {
                Stepper(value: $controller.settings.maxRecordingSeconds, in: AppSettings.Bounds.recordingSeconds, step: 10) {
                    LabeledContent(L("settings.max_recording_label", "Maximum recording length")) {
                        Text(Duration.seconds(controller.settings.maxRecordingSeconds).formatted(.time(pattern: .minuteSecond)))
                            .monospacedDigit()
                    }
                }
                Stepper(value: $controller.settings.pasteDelayMs, in: AppSettings.Bounds.pasteDelay, step: 25) {
                    LabeledContent(L("settings.paste_delay_label", "Paste delay")) {
                        Text("\(controller.settings.pasteDelayMs) ms").monospacedDigit()
                    }
                }
            }

            Section(L("settings.appearance", "Appearance")) {
                if LiquidGlassSupport.isAvailable {
                    Toggle(isOn: $controller.settings.classicMaterials) {
                        Text(L("settings.classic_materials", "Classic look"))
                        Text(L("settings.classic_materials.hint", "Use translucent materials instead of Liquid Glass. Lighter on older Intel Macs. Floating windows switch the next time they open."))
                    }
                } else {
                    Label(L("settings.classic_only", "Liquid Glass needs macOS 26. On this Mac WhisperFly uses the classic translucent look."), systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(L("settings.history", "History")) {
                LabeledContent(L("settings.history.count", "Saved transcriptions")) {
                    Text("\(history.entries.count)")
                }
                HStack {
                    Button(L("settings.history.show", "Show History")) { controller.showHistory() }
                    Button(L("history.clear", "Clear All"), role: .destructive) { confirmClear.value = true }
                        .disabled(history.entries.isEmpty)
                }
            }

            Section(L("settings.setup", "Setup")) {
                Button(L("settings.show_welcome", "Show Welcome Guide")) { controller.showOnboarding() }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L("history.clear_confirm", "Delete all transcriptions?"), isPresented: $confirmClear.value) {
            Button(L("history.clear", "Clear All"), role: .destructive) { history.clear() }
        }
    }
}
