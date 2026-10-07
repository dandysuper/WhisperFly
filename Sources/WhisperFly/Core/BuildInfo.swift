import Foundation

/// Build-time metadata for the running binary.
///
/// These values are stamped into the app bundle's `Info.plist` by
/// `scripts/build-app.sh` — marketing version, build number, git commit SHA,
/// commit date, repository slug and branch. When the app is launched straight
/// from a SwiftPM build product (a plain `swift run WhisperFly`, which has no
/// bundle at all) every value degrades to a placeholder so the app still runs
/// and the updater can report "unknown local revision" instead of crashing.
enum BuildInfo {

    /// `Info.plist` keys written by the build script.
    private enum InfoKey {
        static let commitSHA   = "WhisperFlyCommitSHA"
        static let commitDate  = "WhisperFlyCommitDate"
        static let buildDate   = "WhisperFlyBuildDate"
        static let repository  = "WhisperFlyRepository"
        static let branch      = "WhisperFlyBranch"
    }

    /// Used when `Info.plist` does not name a repository (e.g. a debug build).
    static let defaultRepository = "dandysuper/WhisperFly"
    static let defaultBranch = "master"

    // MARK: - Bundle identity

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.dandysuper.WhisperFly"
    }

    static var displayName: String {
        (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (Bundle.main.infoDictionary?["CFBundleName"] as? String)
            ?? "WhisperFly"
    }

    /// Marketing version, e.g. `2.1.0`.
    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// Monotonic build number, e.g. `7`.
    static var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
    }

    // MARK: - Source revision

    /// Full 40-character git SHA the bundle was built from, or `nil` when the
    /// build script did not stamp one (plain `swift run`).
    static var commitSHA: String? {
        guard let raw = Bundle.main.infoDictionary?[InfoKey.commitSHA] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// First 7 characters of `commitSHA`, for display.
    static var shortCommitSHA: String? {
        commitSHA.map { String($0.prefix(7)) }
    }

    /// ISO-8601 author date of the stamped commit.
    static var commitDate: Date? {
        iso8601Date(from: Bundle.main.infoDictionary?[InfoKey.commitDate] as? String)
    }

    /// ISO-8601 timestamp of when the bundle was assembled.
    static var buildDate: Date? {
        iso8601Date(from: Bundle.main.infoDictionary?[InfoKey.buildDate] as? String)
    }

    // MARK: - Update source

    /// GitHub repository in `owner/name` form.
    static var repository: String {
        let value = (Bundle.main.infoDictionary?[InfoKey.repository] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return defaultRepository }
        return value
    }

    /// Branch whose commits are treated as "latest".
    static var branch: String {
        let value = (Bundle.main.infoDictionary?[InfoKey.branch] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return defaultBranch }
        return value
    }

    // MARK: - Runtime shape

    /// `true` when running from a real `.app` bundle (an installed build), as
    /// opposed to a bare executable produced by `swift run`.
    static var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Absolute path of the running `.app`, when there is one.
    static var appBundleURL: URL? {
        isAppBundle ? Bundle.main.bundleURL : nil
    }

    /// `2.1.0 (7) · a1b2c3d`, or a development marker when nothing was stamped.
    static var displayVersion: String {
        var text = "\(version) (\(buildNumber))"
        if let short = shortCommitSHA {
            text += " · \(short)"
        } else {
            text += " · dev"
        }
        return text
    }

    // MARK: - Helpers

    private static func iso8601Date(from raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }
}
