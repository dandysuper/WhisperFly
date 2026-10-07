import Testing
import Foundation
import ScreenCaptureKit
@testable import WhisperFly

// MARK: - Helpers

/// A throwaway `UserDefaults` domain per test, so nothing leaks into the
/// developer's real preferences or between tests.
private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "test.whisperfly.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func sampleJSON(_ json: String) -> Data {
    Data(json.utf8)
}

// MARK: - AppSettings decoding

@Suite("AppSettings decoding")
struct AppSettingsDecodingTests {

    @Test func missingKeysFallBackToDefaults() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: sampleJSON("{}"))
        #expect(settings == AppSettings())
    }

    @Test func legacyLabelRawValuesMigrate() throws {
        // Releases up to 2.x persisted the user-visible labels (and the
        // since-removed NIM backend) instead of stable identifiers.
        let data = sampleJSON("""
        {
            "audioSource": "Microphone",
            "transcriptionBackend": "NIM Canary",
            "hotkey": "⌘⇧Space",
            "rewriteMode": "Translate to English"
        }
        """)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.audioSource == .microphone)
        #expect(settings.transcriptionBackend == .groqWhisper)
        #expect(settings.hotkey == .commandShiftSpace)
        #expect(settings.rewriteMode == .translate)
    }

    @Test func unknownEnumValuesFallBack() throws {
        let data = sampleJSON("""
        {
            "audioSource": "Telepathy",
            "transcriptionBackend": "Skynet",
            "hotkey": "CtrlAltDel"
        }
        """)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.audioSource == .microphone)
        #expect(settings.transcriptionBackend == .groqWhisper)
        #expect(settings.hotkey == .commandShiftSpace)
    }

    @Test func outOfBoundsNumbersAreClamped() throws {
        let data = sampleJSON("""
        {
            "maxRecordingSeconds": 9999,
            "pasteDelayMs": 1,
            "updateCheckIntervalHours": 0
        }
        """)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.maxRecordingSeconds == 300)
        #expect(settings.pasteDelayMs == 50)
        #expect(settings.updateCheckIntervalHours == 1)
    }

    @Test func wrongTypedValuesFallBack() throws {
        let data = sampleJSON("""
        {
            "geminiRewriteEnabled": "yes",
            "maxRecordingSeconds": "two minutes",
            "groqApiKey": 42
        }
        """)
        let settings = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(settings.geminiRewriteEnabled == true)
        #expect(settings.maxRecordingSeconds == 120)
        #expect(settings.groqApiKey == "")
    }

    @Test func roundTripKeepsCustomValues() throws {
        var settings = AppSettings()
        settings.groqApiKey = "gsk_test"
        settings.audioSource = .systemAudio
        settings.hotkey = .controlOptionSpace
        settings.updateCheckIntervalHours = 12

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        #expect(decoded == settings)
    }
}

// MARK: - SettingsStore

@Suite("SettingsStore")
struct SettingsStoreTests {

    @Test func saveAndLoadRoundTrip() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)

        var settings = AppSettings()
        settings.groqApiKey = "gsk_roundtrip"
        settings.updateRepository = "owner/repo"
        store.save(settings)

        #expect(store.load() == settings)
    }

    @Test func corruptBlobIsBackedUpNotWiped() {
        let defaults = makeIsolatedDefaults()
        let store = SettingsStore(defaults: defaults)

        let garbage = Data("not json at all".utf8)
        defaults.set(garbage, forKey: "whisperflow_settings")

        let loaded = store.load()
        #expect(loaded == AppSettings() || SettingsStore.readEnvironmentFile() != nil)
        #expect(defaults.data(forKey: "whisperflow_settings_corrupt_backup") == garbage)
        // The unreadable blob itself is left in place until a successful save
        // overwrites it.
        #expect(defaults.data(forKey: "whisperflow_settings") == garbage)
    }

    @Test func parseEnvironmentHandlesQuotesAndComments() {
        let parsed = SettingsStore.parseEnvironment("""
        # a comment
        GROQ_API_KEY="gsk-123"
        OPENROUTER_API_KEY='sk-or-456'
        EMPTY=
        this line has no equals sign
          SPACED  =  value
        """)
        #expect(parsed["GROQ_API_KEY"] == "gsk-123")
        #expect(parsed["OPENROUTER_API_KEY"] == "sk-or-456")
        #expect(parsed["EMPTY"] == "")
        #expect(parsed["SPACED"] == "value")
        #expect(parsed.count == 4)
    }
}

// MARK: - TranscriptionHistory

@MainActor
@Suite("TranscriptionHistory")
struct TranscriptionHistoryTests {

    @Test func addPersistsAcrossInstances() {
        let defaults = makeIsolatedDefaults()
        let history = TranscriptionHistory(defaults: defaults)
        history.add(TranscriptionEntry(text: "hello world", source: .microphone, latency: 1.5))

        let reloaded = TranscriptionHistory(defaults: defaults)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries.first?.text == "hello world")
        #expect(reloaded.entries.first?.source == .microphone)
    }

    @Test func entriesAreCapped() {
        let defaults = makeIsolatedDefaults()
        let history = TranscriptionHistory(defaults: defaults)
        for index in 0..<150 {
            history.add(TranscriptionEntry(text: "entry \(index)", source: .file))
        }
        #expect(history.entries.count == 100)
        // Newest first, and the oldest 50 were dropped.
        #expect(history.entries.first?.text == "entry 149")
        #expect(history.entries.last?.text == "entry 50")
    }

    @Test func corruptArrayIsBackedUpAndDropped() {
        let defaults = makeIsolatedDefaults()
        let garbage = Data("][ not an array".utf8)
        defaults.set(garbage, forKey: "whisperfly_history")

        let history = TranscriptionHistory(defaults: defaults)
        #expect(history.entries.isEmpty)
        #expect(defaults.data(forKey: "whisperfly_history_corrupt_backup") == garbage)
    }

    @Test func unreadableEntriesAreDroppedIndividually() throws {
        let defaults = makeIsolatedDefaults()
        // Per-field decode fills wrong-typed fields from defaults, so a wrong
        // typed field survives as fallbacks; only an element that is not an
        // object at all is dropped wholesale.
        let good = TranscriptionEntry(text: "survivor", source: .microphone)
        let goodData = try JSONEncoder().encode([good])
        var array = try JSONSerialization.jsonObject(with: goodData) as! [[String: Any]]
        array.append(["text": 42])  // wrong-typed field: entry survives with fallbacks
        let mixed: [Any] = array + ["barely an entry"]  // not an object: dropped
        let mixedData = try JSONSerialization.data(withJSONObject: mixed)

        defaults.set(mixedData, forKey: "whisperfly_history")

        let history = TranscriptionHistory(defaults: defaults)
        #expect(history.entries.count == 2)
        #expect(history.entries.first?.text == "survivor")
        #expect(history.entries.last?.text == "")  // the fallback-only entry
    }
}

// MARK: - GitHub client decoding

@Suite("GitHubClient decoding")
struct GitHubClientDecodingTests {

    @Test func decodeCommitParsesFields() throws {
        let commit = try GitHubClient.decodeCommit(sampleJSON("""
        {
            "sha": "abc123def4567890abc123def4567890abc12345",
            "commit": {
                "message": "fix: stabilize system audio\\n\\nlonger body",
                "author": { "name": "Daniil", "date": "2026-10-07T06:00:00Z" }
            },
            "html_url": "https://github.com/dandysuper/WhisperFly/commit/abc1234"
        }
        """))
        #expect(commit.shortSHA == "abc123d")
        #expect(commit.headline == "fix: stabilize system audio")
        #expect(commit.authorName == "Daniil")
        #expect(commit.authoredAt != nil)
        #expect(commit.htmlURL?.absoluteString == "https://github.com/dandysuper/WhisperFly/commit/abc1234")
    }

    @Test func decodeCommitWithoutShaThrows() {
        #expect(throws: (any Error).self) {
            _ = try GitHubClient.decodeCommit(sampleJSON(#"{"commit": {}}"#))
        }
    }

    @Test func decodeReleaseParsesAssets() throws {
        let release = try GitHubClient.decodeRelease(sampleJSON("""
        {
            "tag_name": "v2.1.0",
            "name": "WhisperFly 2.1.0",
            "published_at": "2026-10-01T12:00:00Z",
            "html_url": "https://github.com/dandysuper/WhisperFly/releases/tag/v2.1.0",
            "assets": [
                { "name": "WhisperFly-arm64.dmg", "browser_download_url": "https://example.com/arm64.dmg", "size": 1463400 },
                { "name": "WhisperFly-intel.dmg", "browser_download_url": "https://example.com/intel.dmg", "size": 1480305 }
            ]
        }
        """))
        #expect(release.version == "2.1.0")
        #expect(release.assets.count == 2)
        #expect(release.assets.allSatisfy { $0.isDiskImage })
    }

    @Test func decodeReleaseWithoutTagThrows() {
        #expect(throws: (any Error).self) {
            _ = try GitHubClient.decodeRelease(sampleJSON(#"{"assets": []}"#))
        }
    }
}

// MARK: - Release asset selection

@Suite("ReleaseAsset selection")
struct ReleaseAssetTests {

    private func asset(_ name: String) -> ReleaseAsset {
        ReleaseAsset(name: name, downloadURL: URL(string: "https://example.com/\(name)")!, sizeBytes: 1)
    }

    @Test func prefersArchitectureMatch() {
        let assets = [asset("WhisperFly.dmg"), asset("WhisperFly-intel.dmg"), asset("WhisperFly-arm64.dmg")]
        #expect(ReleaseAsset.preferredDMG(from: assets, isAppleSilicon: true)?.name == "WhisperFly-arm64.dmg")
        #expect(ReleaseAsset.preferredDMG(from: assets, isAppleSilicon: false)?.name == "WhisperFly-intel.dmg")
    }

    @Test func universalImageIsPreferredOverArchSpecificWhenNoMatch() {
        let assets = [asset("WhisperFly-arm64.dmg"), asset("WhisperFly.dmg")]
        #expect(ReleaseAsset.preferredDMG(from: assets, isAppleSilicon: false)?.name == "WhisperFly.dmg")
    }

    @Test func nonDiskImagesAreIgnored() {
        let assets = [asset("checksums.txt"), asset("WhisperFly.zip")]
        #expect(ReleaseAsset.preferredDMG(from: assets, isAppleSilicon: true) == nil)
    }
}

// MARK: - Update models

@Suite("UpdateModels")
struct UpdateModelsTests {

    @Test func busyPhases() {
        #expect(UpdateInstallPhase.downloading(fraction: 0.5).isBusy)
        #expect(UpdateInstallPhase.verifying.isBusy)
        #expect(UpdateInstallPhase.installing.isBusy)
        #expect(UpdateInstallPhase.rebuilding.isBusy)
        #expect(UpdateInstallPhase.relaunching.isBusy)
        #expect(!UpdateInstallPhase.idle.isBusy)
        #expect(!UpdateInstallPhase.finished.isBusy)
        #expect(!UpdateInstallPhase.failed("boom").isBusy)
    }

    @Test func downloadDescriptionFormatsPercent() {
        #expect(UpdateInstallPhase.downloading(fraction: 0.42).description.contains("42"))
        #expect(UpdateInstallPhase.downloading(fraction: nil).description.contains("Downloading"))
    }

    @Test func updateStatusExposesRemoteCommit() {
        let commit = RemoteCommit(
            sha: String(repeating: "a", count: 40),
            message: "feat: something",
            authorName: nil, authoredAt: nil, htmlURL: nil
        )
        #expect(UpdateStatus.updateAvailable(commit).remoteCommit == commit)
        #expect(UpdateStatus.updateAvailable(commit).isUpdateAvailable)
        #expect(!UpdateStatus.localRevisionUnknown(commit).isUpdateAvailable)
        #expect(UpdateStatus.upToDate.remoteCommit == nil)
    }
}

// MARK: - Permission state mapping

@Suite("PermissionState mapping")
struct PermissionStateTests {

    private func scError(_ code: SCStreamError.Code) -> NSError {
        NSError(domain: SCStreamErrorDomain, code: code.rawValue)
    }

    @Test func screenCaptureRefusalsMapToDenied() {
        #expect(PermissionState(screenCaptureError: scError(.userDeclined)) == .denied)
        #expect(PermissionState(screenCaptureError: scError(.missingEntitlements)) == .denied)
        // macOS 15+ reports a missing Screen Recording grant through this code.
        #expect(PermissionState(screenCaptureError: scError(.failedToStartAudioCapture)) == .denied)
    }

    @Test func transientFailuresStayUnknown() {
        // `failedToStartMicrophoneCapture` is a real refusal that this mapping
        // deliberately does not call "denied", and an unrecognised code in the
        // right domain must not masquerade as a permission verdict either.
        if #available(macOS 15.0, *) {
            #expect(PermissionState(screenCaptureError: scError(.failedToStartMicrophoneCapture)) == .unknown)
        }
        #expect(PermissionState(screenCaptureError: NSError(domain: SCStreamErrorDomain, code: 99999)) == .unknown)
        #expect(PermissionState(screenCaptureError: NSError(domain: "something else", code: 30)) == .unknown)
    }

    @Test func onlyGrantedCountsAsGranted() {
        #expect(PermissionState.granted.isGranted)
        #expect(!PermissionState.denied.isGranted)
        #expect(!PermissionState.notDetermined.isGranted)
        #expect(!PermissionState.restricted.isGranted)
        #expect(!PermissionState.unknown.isGranted)
    }
}

// MARK: - Code signature diagnostics

@Suite("CodeSignatureInfo")
struct CodeSignatureInfoTests {

    private func info(
        isAdHoc: Bool,
        team: String?,
        requirement: String?
    ) -> CodeSignatureInfo {
        CodeSignatureInfo(
            identifier: "com.dandysuper.WhisperFly",
            teamIdentifier: team,
            isAdHoc: isAdHoc,
            hasHardenedRuntime: true,
            designatedRequirement: requirement,
            cdHash: nil
        )
    }

    @Test func stableIdentityNeedsTeamAndNonHashRequirement() {
        #expect(info(isAdHoc: false, team: "ABCDE12345",
                     requirement: "anchor apple generic and identifier ...").hasStableIdentity)
        #expect(!info(isAdHoc: true, team: "ABCDE12345",
                      requirement: "anchor apple generic").hasStableIdentity)
        #expect(!info(isAdHoc: false, team: nil,
                      requirement: "anchor apple generic").hasStableIdentity)
        #expect(!info(isAdHoc: false, team: "ABCDE12345",
                      requirement: "identifier ... and cdhash H\"...\"").hasStableIdentity)
    }

    @Test func everyUnstableShapeProducesADiagnosis() {
        #expect(info(isAdHoc: true, team: nil, requirement: nil).persistenceDiagnosis != nil)
        #expect(info(isAdHoc: false, team: nil, requirement: "anchor apple generic").persistenceDiagnosis != nil)
        #expect(info(isAdHoc: false, team: "X", requirement: "cdhash H\"..\"").persistenceDiagnosis != nil)
        #expect(info(isAdHoc: false, team: "X", requirement: "anchor apple generic").persistenceDiagnosis == nil)
    }
}
