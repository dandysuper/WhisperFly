import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "UpdateInstaller")

/// Replaces the running app with a newer build.
///
/// Two strategies, because the app can be running in two different shapes:
/// an installed `.app` bundle (replace it from a release disk image) or a build
/// product launched from a source checkout (pull and rebuild). Both finish by
/// relaunching, and neither ever leaves the user with a half-written bundle.
enum UpdateInstaller {

    enum InstallError: LocalizedError {
        case notAnAppBundle
        case mountFailed(String)
        case mountPointMissing
        case noAppInDiskImage
        case bundleIdentifierMismatch(found: String?, expected: String)
        case noWritableDestination(String)
        case copyFailed(String)
        case sourceCheckoutMissing
        case commandFailed(tool: String, status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .notAnAppBundle:
                return L("update.install.not_bundle",
                         "This build is not running from an application bundle, so it cannot replace itself. Use the source rebuild method instead.")
            case .mountFailed(let detail):
                return L("update.install.mount_failed", "Could not open the downloaded disk image: %@.", detail)
            case .mountPointMissing:
                return L("update.install.mount_point", "The disk image did not mount where expected.")
            case .noAppInDiskImage:
                return L("update.install.no_app", "The disk image does not contain an application.")
            case .bundleIdentifierMismatch(let found, let expected):
                return L("update.install.identifier_mismatch",
                         "The downloaded app identifies itself as %@ instead of %@. Refusing to install it.",
                         found ?? "unknown", expected)
            case .noWritableDestination(let path):
                return L("update.install.destination",
                         "WhisperFly cannot write to %@. Move the app somewhere you own, or reinstall it there first.", path)
            case .copyFailed(let detail):
                return L("update.install.copy_failed", "Copying the new version failed: %@.", detail)
            case .sourceCheckoutMissing:
                return L("update.install.no_checkout",
                         "No git checkout was found to pull from. Choose the release disk image method instead.")
            case .commandFailed(let tool, let status, let output):
                let detail = output.isEmpty ? "exit status \(status)" : output
                return L("update.install.command_failed", "%@ failed: %@.", tool, detail)
            }
        }
    }

    // MARK: - Disk image path

    /// Installs `diskImage` over the currently running bundle.
    ///
    /// The replacement is staged beside the destination and only swapped in once
    /// the download has been verified, so a failure at any earlier point leaves
    /// the installed app untouched. The caller owns the relaunch: this method is
    /// `async` and nonisolated so the mount and copy run off the main thread, and
    /// `NSApplication.terminate` can only be reached from the main actor.
    static func install(diskImage: URL, targetBundle: URL? = BuildInfo.appBundleURL) async throws {
        guard let targetBundle, BuildInfo.isAppBundle else {
            throw InstallError.notAnAppBundle
        }

        let mountPoint = try mount(diskImage: diskImage)
        defer { unmount(mountPoint: mountPoint) }

        let sourceApp = try findApplication(in: mountPoint)
        try verify(bundleIdentifierOf: sourceApp, matches: BuildInfo.bundleIdentifier)

        let parent = targetBundle.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw InstallError.noWritableDestination(parent.path)
        }

        // Stage the new bundle next to the old one, on the same volume so the
        // final move is a rename rather than a cross-device copy.
        let staged = parent.appendingPathComponent(".WhisperFly-update-\(UUID().uuidString).app")
        try copy(from: sourceApp, to: staged)
        defer { try? FileManager.default.removeItem(at: staged) }

        let backup = parent.appendingPathComponent(".WhisperFly-backup-\(UUID().uuidString).app")
        try FileManager.default.moveItem(at: targetBundle, to: backup)

        do {
            try FileManager.default.moveItem(at: staged, to: targetBundle)
        } catch {
            // Put the original back so the user is never left without an app.
            try? FileManager.default.moveItem(at: backup, to: targetBundle)
            throw InstallError.copyFailed(error.localizedDescription)
        }

        try? FileManager.default.removeItem(at: backup)
        stripQuarantine(from: targetBundle)
        log.info("Installed update from \(diskImage.lastPathComponent, privacy: .public)")
    }

    // MARK: - Source checkout path

    /// Pulls the tracked branch into `checkout` and rebuilds it.
    ///
    /// The rebuild reuses the repository's own `scripts/build-app.sh`, so a
    /// developer running from a checkout gets exactly the same bundle the release
    /// process produces rather than a bespoke one-off build. Like `install`, the
    /// caller owns the relaunch.
    static func rebuildFromSource(checkout: URL, branch: String) async throws {
        guard FileManager.default.fileExists(atPath: checkout.appendingPathComponent(".git").path) else {
            throw InstallError.sourceCheckoutMissing
        }

        _ = try run("/usr/bin/git", ["fetch", "--prune", "origin"], in: checkout)
        _ = try run("/usr/bin/git", ["checkout", branch], in: checkout)
        _ = try run("/usr/bin/git", ["pull", "--ff-only", "origin", branch], in: checkout)

        let buildScript = checkout.appendingPathComponent("scripts/build-app.sh")
        guard FileManager.default.isExecutableFile(atPath: buildScript.path) else {
            throw InstallError.sourceCheckoutMissing
        }
        _ = try run(buildScript.path, [], in: checkout)
    }

    /// Locates a git checkout for the tracked repository.
    ///
    /// Checks an explicit path first, then walks up from the running bundle and
    /// from the current working directory — which is where a `swift run` process
    /// normally lives.
    static func locateSourceCheckout(explicitPath: String?) -> URL? {
        var candidates: [URL] = []
        if let explicitPath, !explicitPath.isEmpty {
            candidates.append(URL(fileURLWithPath: explicitPath, isDirectory: true))
        }
        if let bundle = BuildInfo.appBundleURL {
            candidates.append(bundle)
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))

        for candidate in candidates {
            var directory = candidate
            for _ in 0..<8 {
                let gitEntry = directory.appendingPathComponent(".git")
                let packageManifest = directory.appendingPathComponent("Package.swift")
                if FileManager.default.fileExists(atPath: gitEntry.path),
                   FileManager.default.fileExists(atPath: packageManifest.path) {
                    return directory
                }
                let parent = directory.deletingLastPathComponent()
                if parent.path == directory.path { break }
                directory = parent
            }
        }
        return nil
    }

    // MARK: - Disk image plumbing

    private static func mount(diskImage: URL) throws -> URL {
        let mountPoint = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("whisperfly-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)

        do {
            _ = try run("/usr/bin/hdiutil", [
                "attach", diskImage.path,
                "-nobrowse", "-readonly", "-noverify",
                "-mountpoint", mountPoint.path
            ], in: nil)
        } catch {
            throw InstallError.mountFailed(error.localizedDescription)
        }

        guard FileManager.default.fileExists(atPath: mountPoint.path) else {
            throw InstallError.mountPointMissing
        }
        return mountPoint
    }

    private static func unmount(mountPoint: URL) {
        _ = try? run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"], in: nil)
        try? FileManager.default.removeItem(at: mountPoint)
    }

    private static func findApplication(in mountPoint: URL) throws -> URL {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw InstallError.noAppInDiskImage
        }
        return app
    }

    private static func verify(bundleIdentifierOf app: URL, matches expected: String) throws {
        let infoPlist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ) as? [String: Any] else {
            throw InstallError.bundleIdentifierMismatch(found: nil, expected: expected)
        }
        let found = plist["CFBundleIdentifier"] as? String
        guard found == expected else {
            throw InstallError.bundleIdentifierMismatch(found: found, expected: expected)
        }
    }

    private static func copy(from source: URL, to destination: URL) throws {
        do {
            // `ditto` preserves the signature, extended attributes and symlinks
            // that a plain FileManager copy can flatten.
            _ = try run("/usr/bin/ditto", [source.path, destination.path], in: nil)
        } catch {
            throw InstallError.copyFailed(error.localizedDescription)
        }
    }

    /// Removes the quarantine flag so the freshly installed bundle launches
    /// without the "downloaded from the internet" gate.
    private static func stripQuarantine(from bundle: URL) {
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", bundle.path], in: nil)
    }

    // MARK: - Process helper

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String], in directory: URL?) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            throw InstallError.commandFailed(
                tool: (executable as NSString).lastPathComponent,
                status: -1,
                output: error.localizedDescription
            )
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw InstallError.commandFailed(
                tool: (executable as NSString).lastPathComponent,
                status: process.terminationStatus,
                output: text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return text
    }
}
