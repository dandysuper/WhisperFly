import Foundation
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "Settings")

/// Persists `AppSettings` in `UserDefaults`.
///
/// Two behaviours matter here and both were previously wrong:
///
/// - **A failed decode must not silently reset the app.** The old store wrapped
///   decoding in `try?` and fell through to `loadFromEnv()`, which returns
///   defaults. Combined with `AppSettings`'s strict synthesised decoder, that
///   turned any added field into a full preference wipe. The stored blob is now
///   kept as-is and copied to a backup key when it cannot be read, so nothing a
///   user configured is destroyed by an upgrade.
/// - **The `.env` fallback path was unreachable.** It looked at
///   `<bundle>/../.env`, i.e. `/Applications/.env`, and at the process working
///   directory, which is `/` for a LaunchServices-launched app. The search now
///   walks up from the bundle and from the working directory.
///
/// The defaults key keeps its original spelling (`whisperflow_settings`) on
/// purpose — renaming it would abandon the settings of every existing install.
final class SettingsStore: @unchecked Sendable {

    private let storageKey = "whisperflow_settings"
    private let corruptBackupKey = "whisperflow_settings_corrupt_backup"
    private let defaults: UserDefaults

    /// `defaults` exists so tests can run against an isolated suite; production
    /// callers always use the standard defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: storageKey) else {
            return loadFromEnvironment()
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            // Keep the unreadable blob so the failure is diagnosable rather than
            // invisible, then continue with defaults.
            log.error("Stored settings could not be decoded: \(error.localizedDescription, privacy: .public). A backup was kept.")
            defaults.set(data, forKey: corruptBackupKey)
            return loadFromEnvironment()
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: storageKey)
        } catch {
            log.error("Could not encode settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Environment fallback

    /// Only used on a first run, when there is nothing stored yet.
    ///
    /// API keys are the one thing worth reading from a developer's `.env` so that
    /// `swift run` works without pasting keys into the UI.
    private func loadFromEnvironment() -> AppSettings {
        var settings = AppSettings()
        guard let environment = Self.readEnvironmentFile() else { return settings }

        if let key = environment["GROQ_API_KEY"], !key.isEmpty {
            settings.groqApiKey = key
        }
        if let key = environment["OPENROUTER_API_KEY"], !key.isEmpty {
            settings.openRouterApiKey = key
        }
        return settings
    }

    /// Parses `.env` syntax: `KEY=VALUE` per line, `#` comments, optional
    /// surrounding quotes on the value.
    static func parseEnvironment(_ contents: String) -> [String: String] {
        var values: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            // `omittingEmptySubsequences: false` keeps `KEY=` as an empty value
            // instead of discarding the line.
            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let value = String(parts[1])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            values[key] = value
        }
        return values
    }

    /// Reads and parses the first `.env` found while walking up from the running
    /// bundle and from the current working directory.
    static func readEnvironmentFile() -> [String: String]? {
        guard let url = locateEnvironmentFile(),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        let values = parseEnvironment(contents)
        return values.isEmpty ? nil : values
    }

    /// Searches a few levels above both the app bundle and the working directory.
    static func locateEnvironmentFile() -> URL? {
        var roots: [URL] = []

        let bundle = Bundle.main.bundleURL
        roots.append(bundle.deletingLastPathComponent())

        let workingDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        if workingDirectory.path != "/" {
            roots.append(workingDirectory)
        }

        for root in roots {
            var directory = root
            for _ in 0..<5 {
                let candidate = directory.appendingPathComponent(".env")
                if FileManager.default.isReadableFile(atPath: candidate.path) {
                    return candidate
                }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        return nil
    }
}
