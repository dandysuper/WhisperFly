import Foundation
import AppKit
import Combine
import os.log

private let log = Logger(subsystem: "com.whisperfly", category: "Updater")

/// Compares the running build's commit against the tracked GitHub branch and
/// installs a newer one on request.
///
/// The comparison is commit-based rather than version-based on purpose: the app
/// ships from `master`, so a merged commit is the event that matters, and the
/// version string in `Info.plist` lags behind it.
@MainActor
final class UpdateService: ObservableObject {

    struct Configuration: Sendable, Equatable {
        var repository: String
        var branch: String
        /// Optional personal access token — raises the rate limit and allows
        /// checking a private fork.
        var token: String
        /// Explicit git checkout to pull from when rebuilding from source.
        var sourceCheckoutPath: String
        var automaticallyChecks: Bool
        var checkIntervalHours: Int

        static let `default` = Configuration(
            repository: BuildInfo.defaultRepository,
            branch: BuildInfo.defaultBranch,
            token: "",
            sourceCheckoutPath: "",
            automaticallyChecks: true,
            checkIntervalHours: 6
        )
    }

    @Published private(set) var status: UpdateStatus = .idle
    @Published private(set) var phase: UpdateInstallPhase = .idle
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var latestRelease: RemoteRelease?

    /// Configuration is published so the settings UI can edit it directly.
    @Published var configuration: Configuration

    /// The commit this build was stamped with, or `nil` for an unstamped build.
    let localCommitSHA: String? = BuildInfo.commitSHA

    private var lastAutomaticCheck: Date?

    init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    // MARK: - Derived state

    var localRevisionDescription: String {
        guard let sha = localCommitSHA else {
            return L("update.local.unstamped", "Unstamped development build")
        }
        return String(sha.prefix(7))
    }

    var isBusy: Bool { phase.isBusy }

    /// The install method that can actually work right now.
    var preferredInstallMethod: UpdateInstallMethod {
        if BuildInfo.isAppBundle && latestRelease?.assets.contains(where: \.isDiskImage) == true {
            return .diskImage
        }
        if UpdateInstaller.locateSourceCheckout(explicitPath: configuration.sourceCheckoutPath) != nil {
            return .sourceRebuild
        }
        return BuildInfo.isAppBundle ? .diskImage : .sourceRebuild
    }

    var canInstall: Bool {
        switch status {
        case .updateAvailable: return true
        default: return false
        }
    }

    var detectedCheckout: URL? {
        UpdateInstaller.locateSourceCheckout(explicitPath: configuration.sourceCheckoutPath)
    }

    // MARK: - Checking

    /// Checks whether the branch head has moved past the stamped commit.
    func check() async {
        guard !isBusy else { return }
        status = .checking

        let client = makeClient()

        do {
            let head = try await client.headCommit()
            lastCheckedAt = Date()
            lastAutomaticCheck = lastCheckedAt

            guard let local = localCommitSHA else {
                // Nothing stamped: we cannot tell whether this is newer or older,
                // so surface the head commit without claiming an update.
                latestRelease = try? await client.latestRelease()
                status = .localRevisionUnknown(head)
                return
            }

            if local == head.sha {
                latestRelease = try? await client.latestRelease()
                status = .upToDate
                return
            }

            let isAncestor = try await client.isAncestor(local, of: head.sha)
            latestRelease = try? await client.latestRelease()

            status = isAncestor
                ? .updateAvailable(head)
                : .localRevisionUnknown(head)

            log.info("Update check: local \(local.prefix(7), privacy: .public) vs head \(head.shortSHA, privacy: .public)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failed(message)
            log.error("Update check failed: \(message, privacy: .public)")
        }
    }

    /// Runs the periodic check when the configured interval has elapsed.
    func checkIfDue() async {
        guard configuration.automaticallyChecks else { return }
        let interval = TimeInterval(max(1, configuration.checkIntervalHours) * 3600)
        if let last = lastAutomaticCheck, Date().timeIntervalSince(last) < interval { return }
        await check()
    }

    // MARK: - Installing

    /// Downloads and installs the newer commit using `method`.
    func install(using method: UpdateInstallMethod) async {
        guard !isBusy else { return }
        switch status {
        case .updateAvailable, .localRevisionUnknown:
            break
        default:
            return
        }

        do {
            switch method {
            case .diskImage:
                try await installFromDiskImage()
            case .sourceRebuild:
                try await rebuildFromSource()
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message)
            log.error("Update install failed: \(message, privacy: .public)")
        }
    }

    private func installFromDiskImage() async throws {
        guard let asset = releaseDiskImage() else {
            throw UpdateInstaller.InstallError.noAppInDiskImage
        }

        phase = .downloading(fraction: 0)
        let downloader = UpdateDownloader()
        let file = try await downloader.download(asset) { [weak self] fraction in
            Task { @MainActor in
                self?.phase = .downloading(fraction: fraction)
            }
        }

        phase = .installing
        try await UpdateInstaller.install(diskImage: file)
        relaunch()
    }

    private func rebuildFromSource() async throws {
        guard let checkout = detectedCheckout else {
            throw UpdateInstaller.InstallError.sourceCheckoutMissing
        }
        phase = .rebuilding
        try await UpdateInstaller.rebuildFromSource(checkout: checkout, branch: configuration.branch)
        relaunch()
    }

    /// Replaces the running process with the freshly installed build.
    ///
    /// `PermissionRepair.relaunch()` ends in `NSApplication.terminate`, so on
    /// success this call never returns and nothing after it executes.
    private func relaunch() {
        phase = .relaunching
        PermissionRepair.relaunch()
    }

    private func releaseDiskImage() -> ReleaseAsset? {
        guard let release = latestRelease else { return nil }
        return ReleaseAsset.preferredDMG(
            from: release.assets,
            isAppleSilicon: Self.isAppleSilicon
        )
    }

    private static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("hw.optional.arm64", &value, &size, nil, 0)
        return status == 0 && value == 1
    }

    // MARK: - Helpers

    func openReleasePage() {
        let url = latestRelease?.htmlURL
            ?? status.remoteCommit?.htmlURL
            ?? URL(string: "https://github.com/\(configuration.repository)/commits/\(configuration.branch)")
        if let url { NSWorkspace.shared.open(url) }
    }

    func clearPhase() {
        if case .failed = phase { phase = .idle }
        if phase == .finished { phase = .idle }
    }

    private func makeClient() -> GitHubClient {
        GitHubClient(
            repository: configuration.repository,
            branch: configuration.branch,
            token: configuration.token.isEmpty ? nil : configuration.token
        )
    }
}
