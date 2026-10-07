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
    var transcriptionBackend: TranscriptionBackend = .groqWhisper
    var hotkey: HotkeyPreset = .commandShiftSpace

    // MARK: Rewriting

    var geminiRewriteEnabled: Bool = true
    var rewriteMode: RewriteMode = .cleanup
    var customSystemPrompt: String = ""
    var readAloudEnabled: Bool = false

    // MARK: Capture timing

    var maxRecordingSeconds: Int = 120
    var pasteDelayMs: Int = 120

    // MARK: Credentials

    var groqApiKey: String = ""
    var openRouterApiKey: String = ""
    var openRouterModel: String = "google/gemini-2.5-flash"

    // MARK: Language

    var sourceLanguage: String = "en"
    var targetLanguage: String = "en"

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
    private enum Bounds {
        static let recordingSeconds = 10...300
        static let pasteDelay = 50...500
        static let checkIntervalHours = 1...72
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case audioSource, transcriptionBackend, hotkey
        case geminiRewriteEnabled, rewriteMode, customSystemPrompt, readAloudEnabled
        case maxRecordingSeconds, pasteDelayMs
        case groqApiKey, openRouterApiKey, openRouterModel
        case sourceLanguage, targetLanguage
        case updateRepository, updateBranch, updateToken, updateSourceCheckoutPath
        case updateAutomaticallyChecks, updateCheckIntervalHours
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        audioSource = Self.decodeEnum(
            container, .audioSource, fallback: .microphone, AudioSource.fromPersisted
        )
        transcriptionBackend = Self.decodeEnum(
            container, .transcriptionBackend, fallback: .groqWhisper, TranscriptionBackend.fromPersisted
        )
        hotkey = Self.decodeEnum(
            container, .hotkey, fallback: .commandShiftSpace, HotkeyPreset.fromPersisted
        )
        rewriteMode = Self.decodeEnum(
            container, .rewriteMode, fallback: .cleanup, Self.migrateRewriteMode
        )

        geminiRewriteEnabled = Self.decode(container, .geminiRewriteEnabled, fallback: true)
        readAloudEnabled     = Self.decode(container, .readAloudEnabled, fallback: false)
        customSystemPrompt   = Self.decode(container, .customSystemPrompt, fallback: "")

        maxRecordingSeconds = Self.decode(container, .maxRecordingSeconds, fallback: 120)
            .clamped(to: Bounds.recordingSeconds)
        pasteDelayMs = Self.decode(container, .pasteDelayMs, fallback: 120)
            .clamped(to: Bounds.pasteDelay)

        groqApiKey        = Self.decode(container, .groqApiKey, fallback: "")
        openRouterApiKey  = Self.decode(container, .openRouterApiKey, fallback: "")
        openRouterModel   = Self.decode(container, .openRouterModel, fallback: "google/gemini-2.5-flash")
        sourceLanguage    = Self.decode(container, .sourceLanguage, fallback: "en")
        targetLanguage    = Self.decode(container, .targetLanguage, fallback: "en")

        updateRepository = Self.decode(container, .updateRepository, fallback: BuildInfo.defaultRepository)
        updateBranch     = Self.decode(container, .updateBranch, fallback: BuildInfo.defaultBranch)
        updateToken      = Self.decode(container, .updateToken, fallback: "")
        updateSourceCheckoutPath = Self.decode(container, .updateSourceCheckoutPath, fallback: "")
        updateAutomaticallyChecks = Self.decode(container, .updateAutomaticallyChecks, fallback: true)
        updateCheckIntervalHours = Self.decode(container, .updateCheckIntervalHours, fallback: 6)
            .clamped(to: Bounds.checkIntervalHours)
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
    private static func decodeEnum<E: RawRepresentable>(
        _ container: KeyedDecodingContainer<CodingKeys>,
        _ key: CodingKeys,
        fallback: E,
        _ migrate: (String) -> E?
    ) -> E where E.RawValue == String {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return fallback
        }
        return migrate(raw) ?? fallback
    }

    /// `RewriteMode` lives in `Protocols.swift` and still uses label raw values;
    /// this keeps a renamed label from invalidating a saved preference.
    private static func migrateRewriteMode(_ raw: String) -> RewriteMode? {
        if let mode = RewriteMode(rawValue: raw) { return mode }
        switch raw.lowercased() {
        case "cleanup":              return .cleanup
        case "punctuate":            return .punctuate
        case "translate",
             "translate to english": return .translate
        default:                     return nil
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
