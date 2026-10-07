import Foundation
import AppKit
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "PermissionRepair")

/// Clears stale TCC rows and relaunches the app.
///
/// When a build is re-signed with a different identity, macOS keeps the *old*
/// grant rows pointing at a requirement that no longer matches, so System
/// Settings shows WhisperFly as enabled while the running process is still
/// untrusted. Nothing in the UI can fix that by toggling — the row itself has to
/// go. `tccutil reset` removes the row for the current user without a password,
/// which makes this a one-click repair for the user instead of the manual
/// remove-and-re-add dance the README used to describe.
enum PermissionRepair {

    enum RepairError: LocalizedError {
        case tccutilFailed(service: String, status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .tccutilFailed(let service, let status, let output):
                let detail = output.isEmpty ? "exit status \(status)" : output
                return L("permission.repair.failed",
                         "Could not reset the %@ permission (%@).", service, detail)
            }
        }
    }

    /// Resets one permission for this app's bundle identifier.
    static func reset(_ kind: PermissionKind, bundleIdentifier: String) throws {
        let result = runTCCUtil(["reset", kind.tccServiceName, bundleIdentifier])
        guard result.status == 0 else {
            throw RepairError.tccutilFailed(
                service: kind.title, status: result.status, output: result.output
            )
        }
        log.info("Reset TCC service \(kind.tccServiceName, privacy: .public) for \(bundleIdentifier, privacy: .public)")
    }

    /// Resets every permission WhisperFly uses, for the case where the signature
    /// changed and all three rows are stale at once.
    ///
    /// Returns the kinds whose reset failed. The caller must not relaunch when
    /// this is non-empty: restarting on a half-cleared state would leave the user
    /// with the same broken rows and no explanation.
    @discardableResult
    static func resetAll(bundleIdentifier: String) -> [PermissionKind] {
        var failures: [PermissionKind] = []
        for kind in PermissionKind.allCases {
            let result = runTCCUtil(["reset", kind.tccServiceName, bundleIdentifier])
            if result.status != 0 {
                failures.append(kind)
                log.error("tccutil reset \(kind.tccServiceName, privacy: .public) failed: \(result.output, privacy: .public)")
            }
        }
        if failures.isEmpty {
            log.info("Reset all TCC services for \(bundleIdentifier, privacy: .public)")
        }
        return failures
    }

    /// Relaunches the app so macOS re-evaluates permissions from scratch.
    ///
    /// A detached shell waits for this process to exit before reopening the
    /// bundle, so the replacement never races with a still-terminating instance
    /// (which for an `LSUIElement` menu-bar app would leave two icons behind).
    ///
    /// `@MainActor` because it ends in `NSApplication.terminate`, which is
    /// main-actor isolated.
    @MainActor
    static func relaunch() {
        guard let bundleURL = BuildInfo.appBundleURL else {
            log.warning("Not running from an app bundle; cannot relaunch automatically")
            return
        }

        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while /bin/kill -0 \(pid) 2>/dev/null; do /bin/sleep 0.2; done
        /usr/bin/open -n \(shellQuoted(bundleURL.path))
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
            log.info("Relaunch scheduled for \(bundleURL.path, privacy: .public)")
        } catch {
            log.error("Failed to schedule relaunch: \(error.localizedDescription, privacy: .public)")
            return
        }

        NSApplication.shared.terminate(nil)
    }

    // MARK: - Process plumbing

    private struct CommandResult {
        let status: Int32
        let output: String
    }

    private static func runTCCUtil(_ arguments: [String]) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return CommandResult(status: -1, output: error.localizedDescription)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return CommandResult(status: process.terminationStatus, output: text)
    }

    /// Minimal single-quote escaping for embedding a path in a shell command.
    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
