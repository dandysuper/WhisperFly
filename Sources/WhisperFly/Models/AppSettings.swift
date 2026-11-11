import Foundation

/// Everything the user can configure, and the contract for loading it.
///
/// The type conforms to `Codable` by hand rather than by synthesis. Swift's
/// synthesised decoder throws `keyNotFound` for a key that is absent *even when
/// the property has a default value*, and throws `dataCorrupted` for an enum raw
/// value it does not recognise. With `try?` around the decode — which is what
/// the old `SettingsStore` did — that meant:
///
/// - shipping a release that added one field silently reset every preference on
///   every existing install, API keys included;
/// - renaming an enum case did the same, because the raw values *were* the
///   user-visible labels.
///
/// Decoding here therefore fills each missing or unrecognised key from the
/// default and migrates legacy values, so an upgrade can only ever change what
/// it is explicitly told to change.
struct AppSettings: Codable, Sendable, Equatable {

    // MARK: Behaviour

    var audioSource: AudioSource = .microphone
    /// Fn on its own by default: hold to dictate, tap to toggle.
    var hotkey: HotkeyPreset = .fn
    /// Holding the shortcut records until release; a quick tap toggles.
    var holdToTalkEnabled: Bool = true
    var soundEffectsEnabled: Bool = true
    var insertionMethod: InsertionMethod = .automatic
    var readAloudEnabled: Bool = false
    /// Use the pre-macOS 26 materials even where Liquid Glass is available.
    var classicMaterials: Bool = false

    // MARK: Transcription

    var transcriptionProvider: AIProvider = .groq
    var groqTranscriptionModel: String = "whisper-large-v3-turbo"
    var geminiTranscriptionModel: String = "gemini-3.5-transcribe"
    /// Gemini 3.5 Transcribe "smart" mode: removes filler words, applies spoken
    /// self-corrections and formats lists, numbers and dates.
    var geminiSmartTranscription: Bool = true
    var customTranscriptionModel: String = "whisper-1"
    /// Try the next configured provider when the selected one fails.
    var fallbackEnabled: Bool = true

    // MARK: Rewriting

    var rewriteEnabled: Bool = true
    var rewriteMode: RewriteMode = .cleanup
    var rewriteProvider: AIProvider = .groq
    var groqRewriteModel: String = "openai/gpt-oss-20b"
    var geminiRewriteModel: String = "gemini-3.5-flash-lite"
    var customRewriteModel: String = "gpt-4o-mini"
    var customSystemPrompt: String = ""
    /// Names, jargon and acronyms, comma- or newline-separated. Sent to the
    /// speech engine as recognition hints and to the rewriter as spellings to keep.
    var customVocabulary: String = ""

    // MARK: Capture timing

    var maxRecordingSeconds: Int = 120
    var pasteDelayMs: Int = 120

    // MARK: Credentials

    var groqApiKey: String = ""
    var geminiApiKey: String = ""
    var openRouterApiKey: String = ""
    /// Used for both transcription and rewriting through OpenRouter.
    var openRouterModel: String = "google/gemini-3.5-flash-lite"
    var customBaseURL: String = "https://api.openai.com/v1"
    var customApiKey: String = ""

    // MARK: Language

    var sourceLanguage: String = DictationLanguage.autoCode
    var targetLanguage: String = "en"

    // MARK: Onboarding

    var hasCompletedOnboarding: Bool = false

    // MARK: Updates

    /// GitHub repository (`owner/name`) whose commits are treated as releases.
    var updateRepository: String = BuildInfo.defaultRepository
    var updateBranch: String = BuildInfo.defaultBranch
    /// Optional personal access token — raises the API rate limit and lets a
    /// private fork be checked. Stored in the app's preferences, not the keychain;
    /// it is a read-only token by design.
    var updateToken: String = ""
    /// Explicit git checkout to pull from when rebuilding from source.
    var updateSourceCheckoutPath: String = ""
    var updateAutomaticallyChecks: Bool = true
    var updateCheckIntervalHours: Int = 6

    static let defaults = AppSettings()

    /// Bounds the UI enforces, applied again on load so a hand-edited or corrupt
    /// preference file cannot put the capture pipeline into a nonsensical state.
    enum Bounds {
        static let recordingSeconds = 10...600
        static let pasteDelay = 50...500
        static let checkIntervalHours = 1...72
    }

    // MARK: - Derived

    func apiKey(for provider: AIProvider) -> String {
        switch provider {
        case .groq:       return groqApiKey.trimmed
        case .gemini:     return geminiApiKey.trimmed
        case .openRouter: return openRouterApiKey.trimmed
        case .custom:     return customApiKey.trimmed
        }
    }

    /// A provider is usable once it has a key. A custom server on this machine
    /// or the local network (a whisper.cpp server, say) may run without one.
    func isConfigured(_ provider: AIProvider) -> Bool {
        switch provider {
        case .custom:
            guard let host = URL(string: customBaseURL.trimmed)?.host?.lowercased() else { return false }
            if !customApiKey.trimmed.isEmpty { return true }
            return host == "localhost" || host == "127.0.0.1" || host == "::1" || host.hasSuffix(".local")
        default:
            return !apiKey(for: provider).isEmpty
        }
    }

    func transcriptionModel(for provider: AIProvider) -> String {
        switch provider {
        case .groq:       return groqTranscriptionModel.trimmed
        case .gemini:     return geminiTranscriptionModel.trimmed
        case .openRouter: return openRouterModel.trimmed
        case .custom:     return customTranscriptionModel.trimmed
        }
    }

    func rewriteModel(for provider: AIProvider) -> String {
        switch provider {
        case .groq:       return groqRewriteModel.trimmed
        case .gemini:     return geminiRewriteModel.trimmed
        case .openRouter: return openRouterModel.trimmed
        case .custom:     return customRewriteModel.trimmed
        }
    }

    var vocabularyTerms: [String] {
        customVocabulary
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var language: DictationLanguage { DictationLanguage.lookup(sourceLanguage) }
    var translationTarget: DictationLanguage { DictationLanguage.lookup(targetLanguage) }

    var hasAnyKey: Bool {
        [groqApiKey, geminiApiKey, openRouterApiKey, customApiKey].contains { !$0.trimmed.isEmpty }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case audioSource, hotkey, holdToTalkEnabled, soundEffectsEnabled, insertionMethod, readAloudEnabled
        case classicMaterials
        // `transcriptionBackend` is the 2.x name of `transcriptionProvider`.
        case transcriptionProvider, transcriptionBackend
        case groqTranscriptionModel, geminiTranscriptionModel, geminiSmartTranscription
        case customTranscriptionModel, fallbackEnabled
        // The persisted key keeps its 2.x spelling so existing preferences survive.
        case rewriteEnabled = "geminiRewriteEnabled"
        case rewriteMode, rewriteProvider, groqRewriteModel, geminiRewriteModel, customRewriteModel
        case customSystemPrompt, customVocabulary
        case maxRecordingSeconds, pasteDelayMs
        case groqApiKey, geminiApiKey, openRouterApiKey, openRouterModel, customBaseURL, customApiKey
        case sourceLanguage, targetLanguage
        case hasCompletedOnboarding
        case updateRepository, updateBranch, updateToken, updateSourceCheckoutPath
        case updateAutomaticallyChecks, updateCheckIntervalHours
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults

        audioSource = Self.decodeEnum(container, .audioSource, fallback: d.audioSource, AudioSource.fromPersisted)
        // 3.0 moved dictation to the Fn key. Settings written by 2.x (they have
        // no `transcriptionProvider`) always stored a chord, because that was the
        // only option, so they are switched once; a choice made in 3.0 sticks.
        let writtenBy2x = !container.contains(.transcriptionProvider)
        hotkey = writtenBy2x
            ? .fn
            : Self.decodeEnum(container, .hotkey, fallback: d.hotkey, HotkeyPreset.fromPersisted)
        holdToTalkEnabled = Self.decode(container, .holdToTalkEnabled, fallback: d.holdToTalkEnabled)
        soundEffectsEnabled = Self.decode(container, .soundEffectsEnabled, fallback: d.soundEffectsEnabled)
        insertionMethod = Self.decodeEnum(container, .insertionMethod, fallback: d.insertionMethod, InsertionMethod.init(rawValue:))
        readAloudEnabled = Self.decode(container, .readAloudEnabled, fallback: d.readAloudEnabled)
        classicMaterials = Self.decode(container, .classicMaterials, fallback: d.classicMaterials)

        // Credentials first: the provider migration below looks at them.
        groqApiKey       = Self.decode(container, .groqApiKey, fallback: "")
        geminiApiKey     = Self.decode(container, .geminiApiKey, fallback: "")
        openRouterApiKey = Self.decode(container, .openRouterApiKey, fallback: "")
        openRouterModel  = Self.decode(container, .openRouterModel, fallback: d.openRouterModel)
        customBaseURL    = Self.decode(container, .customBaseURL, fallback: d.customBaseURL)
        customApiKey     = Self.decode(container, .customApiKey, fallback: "")

        if let provider = Self.decodeEnumIfPresent(container, .transcriptionProvider, AIProvider.init(rawValue:)) {
            transcriptionProvider = provider
        } else {
            transcriptionProvider = Self.decodeEnum(
                container, .transcriptionBackend, fallback: d.transcriptionProvider, AIProvider.fromLegacyBackend
            )
        }
        groqTranscriptionModel   = Self.decode(container, .groqTranscriptionModel, fallback: d.groqTranscriptionModel)
        geminiTranscriptionModel = Self.decode(container, .geminiTranscriptionModel, fallback: d.geminiTranscriptionModel)
        geminiSmartTranscription = Self.decode(container, .geminiSmartTranscription, fallback: d.geminiSmartTranscription)
        customTranscriptionModel = Self.decode(container, .customTranscriptionModel, fallback: d.customTranscriptionModel)
        fallbackEnabled          = Self.decode(container, .fallbackEnabled, fallback: d.fallbackEnabled)

        rewriteEnabled = Self.decode(container, .rewriteEnabled, fallback: d.rewriteEnabled)
        rewriteMode = Self.decodeEnum(container, .rewriteMode, fallback: d.rewriteMode, Self.migrateRewriteMode)
        if let provider = Self.decodeEnumIfPresent(container, .rewriteProvider, AIProvider.init(rawValue:)) {
            rewriteProvider = provider
        } else if !openRouterApiKey.trimmed.isEmpty && groqApiKey.trimmed.isEmpty {
            // 2.x always rewrote through OpenRouter. Keep doing that for an
            // install that only ever configured an OpenRouter key.
            rewriteProvider = .openRouter
        } else {
            rewriteProvider = d.rewriteProvider
        }
        groqRewriteModel   = Self.decode(container, .groqRewriteModel, fallback: d.groqRewriteModel)
        geminiRewriteModel = Self.decode(container, .geminiRewriteModel, fallback: d.geminiRewriteModel)
        customRewriteModel = Self.decode(container, .customRewriteModel, fallback: d.customRewriteModel)
        customSystemPrompt = Self.decode(container, .customSystemPrompt, fallback: "")
        customVocabulary   = Self.decode(container, .customVocabulary, fallback: "")

        maxRecordingSeconds = Self.decode(container, .maxRecordingSeconds, fallback: d.maxRecordingSeconds)
            .clamped(to: Bounds.recordingSeconds)
        pasteDelayMs = Self.decode(container, .pasteDelayMs, fallback: d.pasteDelayMs)
            .clamped(to: Bounds.pasteDelay)

        sourceLanguage = Self.decode(container, .sourceLanguage, fallback: d.sourceLanguage)
        targetLanguage = Self.decode(container, .targetLanguage, fallback: d.targetLanguage)

        // An install upgraded from 2.x that already has a key has, in effect,
        // been onboarded; do not greet it with the welcome window.
        let upgradedWithKey = [groqApiKey, geminiApiKey, openRouterApiKey].contains { !$0.trimmed.isEmpty }
        hasCompletedOnboarding = Self.decode(container, .hasCompletedOnboarding, fallback: upgradedWithKey)

        updateRepository = Self.decode(container, .updateRepository, fallback: BuildInfo.defaultRepository)
        updateBranch     = Self.decode(container, .updateBranch, fallback: BuildInfo.defaultBranch)
        updateToken      = Self.decode(container, .updateToken, fallback: "")
        updateSourceCheckoutPath = Self.decode(container, .updateSourceCheckoutPath, fallback: "")
        updateAutomaticallyChecks = Self.decode(container, .updateAutomaticallyChecks, fallback: true)
        updateCheckIntervalHours = Self.decode(container, .updateCheckIntervalHours, fallback: 6)
            .clamped(to: Bounds.checkIntervalHours)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(audioSource, forKey: .audioSource)
        try c.encode(hotkey, forKey: .hotkey)
        try c.encode(holdToTalkEnabled, forKey: .holdToTalkEnabled)
        try c.encode(soundEffectsEnabled, forKey: .soundEffectsEnabled)
        try c.encode(insertionMethod, forKey: .insertionMethod)
        try c.encode(readAloudEnabled, forKey: .readAloudEnabled)
        try c.encode(classicMaterials, forKey: .classicMaterials)
        try c.encode(transcriptionProvider, forKey: .transcriptionProvider)
        try c.encode(groqTranscriptionModel, forKey: .groqTranscriptionModel)
        try c.encode(geminiTranscriptionModel, forKey: .geminiTranscriptionModel)
        try c.encode(geminiSmartTranscription, forKey: .geminiSmartTranscription)
        try c.encode(customTranscriptionModel, forKey: .customTranscriptionModel)
        try c.encode(fallbackEnabled, forKey: .fallbackEnabled)
        try c.encode(rewriteEnabled, forKey: .rewriteEnabled)
        try c.encode(rewriteMode, forKey: .rewriteMode)
        try c.encode(rewriteProvider, forKey: .rewriteProvider)
        try c.encode(groqRewriteModel, forKey: .groqRewriteModel)
        try c.encode(geminiRewriteModel, forKey: .geminiRewriteModel)
        try c.encode(customRewriteModel, forKey: .customRewriteModel)
        try c.encode(customSystemPrompt, forKey: .customSystemPrompt)
        try c.encode(customVocabulary, forKey: .customVocabulary)
        try c.encode(maxRecordingSeconds, forKey: .maxRecordingSeconds)
        try c.encode(pasteDelayMs, forKey: .pasteDelayMs)
        try c.encode(groqApiKey, forKey: .groqApiKey)
        try c.encode(geminiApiKey, forKey: .geminiApiKey)
        try c.encode(openRouterApiKey, forKey: .openRouterApiKey)
        try c.encode(openRouterModel, forKey: .openRouterModel)
        try c.encode(customBaseURL, forKey: .customBaseURL)
        try c.encode(customApiKey, forKey: .customApiKey)
        try c.encode(sourceLanguage, forKey: .sourceLanguage)
        try c.encode(targetLanguage, forKey: .targetLanguage)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try c.encode(updateRepository, forKey: .updateRepository)
        try c.encode(updateBranch, forKey: .updateBranch)
        try c.encode(updateToken, forKey: .updateToken)
        try c.encode(updateSourceCheckoutPath, forKey: .updateSourceCheckoutPath)
        try c.encode(updateAutomaticallyChecks, forKey: .updateAutomaticallyChecks)
        try c.encode(updateCheckIntervalHours, forKey: .updateCheckIntervalHours)
    }

    // MARK: - Decoding helpers

    /// Reads a value, substituting `fallback` when the key is absent or holds
    /// something of the wrong shape. Never throws.
    private static func decode<T: Decodable>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        fallback: T
    ) -> T {
        // `try?` over an optional-returning throwing call flattens to a single
        // optional, so a missing key and a type mismatch both land in the guard.
        guard let decoded = try? container.decodeIfPresent(T.self, forKey: key) else {
            return fallback
        }
        return decoded
    }

    /// Reads a string-backed enum, running the legacy migration when the stored
    /// raw value is not one this build knows about.
    private static func decodeEnum<E>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        fallback: E,
        _ migrate: (String) -> E?
    ) -> E {
        decodeEnumIfPresent(container, key, migrate) ?? fallback
    }

    private static func decodeEnumIfPresent<E>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        _ migrate: (String) -> E?
    ) -> E? {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return migrate(raw)
    }

    /// `RewriteMode` still uses label raw values; this keeps a renamed label
    /// from invalidating a saved preference.
    private static func migrateRewriteMode(_ raw: String) -> RewriteMode? {
        if let mode = RewriteMode(rawValue: raw) { return mode }
        switch raw.lowercased() {
        case "cleanup":              return .cleanup
        case "punctuate":            return .punctuate
        case "professional":         return .professional
        case "custom":               return .custom
        case "translate",
             "translate to english": return .translate
        default:                     return nil
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
