import SwiftUI

/// First-run guide: pick a free engine and paste a key, grant permissions,
/// then try the shortcut in a practice field.
struct OnboardingView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var permissions: PermissionService

    @StateObject private var step = LocalState(0)
    @StateObject private var keyCheck = LocalState<KeyCheckState>(.idle)
    @StateObject private var practice = LocalState("")

    private let stepCount = 4

    var body: some View {
        ZStack {
            backdrop

            VStack(spacing: 0) {
                stepIndicator
                    .padding(.top, 44)

                Group {
                    switch step.value {
                    case 0: welcomeStep
                    case 1: engineStep
                    case 2: permissionsStep
                    default: tryItStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 36)
                .padding(.top, 24)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
                .id(step.value)

                footer
                    .padding(.horizontal, 36)
                    .padding(.bottom, 28)
            }
        }
        .frame(minWidth: 560, minHeight: 560)
        .onAppear { Task { await permissions.refreshAll() } }
    }

    // MARK: - Backdrop

    /// Soft colour fields for the glass to refract.
    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            Circle()
                .fill(Color.purple.opacity(0.28))
                .frame(width: 380)
                .blur(radius: 90)
                .offset(x: -170, y: -190)
            Circle()
                .fill(Color.blue.opacity(0.24))
                .frame(width: 340)
                .blur(radius: 90)
                .offset(x: 200, y: 40)
            Circle()
                .fill(Color.orange.opacity(0.20))
                .frame(width: 300)
                .blur(radius: 90)
                .offset(x: -60, y: 260)
        }
        .ignoresSafeArea()
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { index in
                Capsule()
                    .fill(index == step.value ? Color.accentColor : Color.primary.opacity(0.15))
                    .frame(width: index == step.value ? 22 : 7, height: 7)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step.value)
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 10)
            Image(systemName: "waveform")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(color: .purple.opacity(0.35), radius: 20, y: 10)

            VStack(spacing: 8) {
                Text(L("onboarding.welcome.title", "Dictate anywhere on your Mac"))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(L("onboarding.welcome.body", "Press a shortcut, speak, and polished text appears in whatever app you're typing in. Free cloud speech engines, no model downloads."))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    featureTile("mic.fill", L("onboarding.feature.dictate", "Dictate into any app"), .red)
                    featureTile("sparkles", L("onboarding.feature.polish", "AI cleanup & translation"), .purple)
                    featureTile("speaker.wave.2.fill", L("onboarding.feature.system", "Transcribe system audio & files"), .blue)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func featureTile(_ icon: String, _ text: String, _ tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96)
        .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                L("onboarding.engine.title", "Choose a free speech engine"),
                L("onboarding.engine.body", "Both are free for everyday dictation. Groq is the fastest; Gemini formats your speech as it transcribes. You can add the other later as a fallback.")
            )

            ProviderPicker(
                selection: engineBinding,
                settings: controller.settings,
                providers: [.groq, .gemini]
            )

            let provider = controller.settings.transcriptionProvider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("onboarding.engine.key", "%@ API key", provider.displayName))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if let url = provider.keyURL {
                        Link(destination: url) {
                            Label(L("onboarding.engine.get_key", "Create a free key"), systemImage: "arrow.up.right.square")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
                HStack(spacing: 8) {
                    SecureField("", text: keyBinding(provider), prompt: Text(provider.keyPlaceholder))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Button {
                        verify(provider)
                    } label: {
                        if keyCheck.value == .checking {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(L("settings.verify", "Verify"))
                        }
                    }
                    .glassButton()
                    .disabled(!controller.settings.isConfigured(provider) || keyCheck.value == .checking)
                }
                switch keyCheck.value {
                case .valid:
                    Label(L("settings.key_valid", "Key works"), systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "xmark.octagon.fill")
                        .font(.caption).foregroundStyle(.red)
                default:
                    Text(provider == .groq
                         ? L("onboarding.engine.groq_steps", "Sign in at console.groq.com, open API Keys, create a key and paste it here. It starts with gsk_.")
                         : L("onboarding.engine.gemini_steps", "Sign in at aistudio.google.com, choose Get API key, create a key and paste it here."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                L("onboarding.permissions.title", "Allow access"),
                L("onboarding.permissions.body", "macOS asks for each of these once. Screen Recording is only needed to transcribe system audio.")
            )

            VStack(spacing: 4) {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(
                        kind: kind,
                        state: permissions.state(for: kind),
                        onRequest: { controller.requestPermission(kind) },
                        onOpenSettings: { permissions.openSettings(for: kind) },
                        onRefresh: { Task { await permissions.refresh(kind) } }
                    )
                    if kind != PermissionKind.allCases.last { Divider() }
                }
            }
            .padding(16)
            .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))

            Button(L("settings.permissions.recheck", "Check Again")) {
                Task { await permissions.refreshAll() }
            }
            .glassButton()
        }
    }

    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(
                L("onboarding.try.title", "Try it"),
                controller.settings.hotkey.isFunctionKey
                    ? (controller.settings.holdToTalkEnabled
                        ? L("onboarding.try.body_fn_hold", "Click in the box, then hold fn, speak, and let go. A quick tap on fn starts and stops recording instead. Esc cancels.")
                        : L("onboarding.try.body_fn_toggle", "Click in the box, tap fn, speak, and tap fn again. Esc cancels."))
                    : (controller.settings.holdToTalkEnabled
                        ? L("onboarding.try.body_hold", "Click in the box, then hold the shortcut, speak, and let go. A quick tap starts and stops recording instead. Esc cancels.")
                        : L("onboarding.try.body_toggle", "Click in the box, press the shortcut, speak, and press it again. Esc cancels."))
            )

            HStack(spacing: 12) {
                KeyCaps(keys: controller.settings.hotkey.keyCaps, size: 15)
                Picker("", selection: $controller.settings.hotkey) {
                    ForEach(AppSettings.HotkeyPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
                Toggle(L("settings.hold_to_talk", "Hold to talk"), isOn: $controller.settings.holdToTalkEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            TextEditor(text: $practice.value)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 140)
                .liquidGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if practice.value.isEmpty {
                        Text(L("onboarding.try.placeholder", "Your words will appear here…"))
                            .font(.system(size: 14))
                            .foregroundStyle(.tertiary)
                            .padding(17)
                            .allowsHitTesting(false)
                    }
                }

            if let conflict = controller.fnKeyConflict {
                FnConflictNotice(conflict: conflict)
            }

            if let error = controller.hotkeyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func stepTitle(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(body)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if step.value > 0 {
                Button(L("onboarding.back", "Back")) { go(step.value - 1) }
                    .glassButton()
                    .controlSize(.large)
            } else {
                Button(L("onboarding.skip", "Skip")) { controller.completeOnboarding() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(primaryTitle) {
                if step.value >= stepCount - 1 {
                    controller.completeOnboarding()
                } else {
                    go(step.value + 1)
                }
            }
            .glassButton(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(step.value == 1 && !controller.isTranscriptionConfigured)
        }
    }

    private var primaryTitle: String {
        switch step.value {
        case 0:             return L("onboarding.start", "Get Started")
        case stepCount - 1: return L("onboarding.finish", "Finish")
        default:            return L("onboarding.continue", "Continue")
        }
    }

    private func go(_ index: Int) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
            step.value = max(0, min(stepCount - 1, index))
        }
    }

    // MARK: - Engine helpers

    /// Choosing an engine here also routes rewriting through it, so one free
    /// key gives the whole pipeline.
    private var engineBinding: Binding<AIProvider> {
        Binding(
            get: { controller.settings.transcriptionProvider },
            set: { provider in
                keyCheck.value = .idle
                controller.settings.transcriptionProvider = provider
                if !controller.settings.isConfigured(controller.settings.rewriteProvider) || controller.settings.rewriteProvider != provider {
                    controller.settings.rewriteProvider = provider
                }
            }
        )
    }

    private func keyBinding(_ provider: AIProvider) -> Binding<String> {
        Binding(
            get: { provider == .groq ? controller.settings.groqApiKey : controller.settings.geminiApiKey },
            set: { value in
                keyCheck.value = .idle
                if provider == .groq {
                    controller.settings.groqApiKey = value
                } else {
                    controller.settings.geminiApiKey = value
                }
            }
        )
    }

    private func verify(_ provider: AIProvider) {
        keyCheck.value = .checking
        let settings = controller.settings
        Task {
            do {
                try await ProviderKeyValidator.validate(provider, settings: settings)
                keyCheck.value = .valid
            } catch {
                keyCheck.value = .failed(error.localizedDescription)
            }
        }
    }
}
