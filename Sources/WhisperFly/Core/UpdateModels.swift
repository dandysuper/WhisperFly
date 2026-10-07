import Foundation

/// One commit on the tracked branch, as GitHub reports it.
struct RemoteCommit: Sendable, Equatable, Identifiable {
    let sha: String
    let message: String
    let authorName: String?
    let authoredAt: Date?
    let htmlURL: URL?

    var id: String { sha }
    var shortSHA: String { String(sha.prefix(7)) }

    /// First line of the commit message.
    var headline: String {
        message.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? message
    }
}

/// A downloadable artifact attached to a GitHub release.
struct ReleaseAsset: Sendable, Equatable {
    let name: String
    let downloadURL: URL
    let sizeBytes: Int

    var isDiskImage: Bool {
        name.lowercased().hasSuffix(".dmg")
    }

    /// Prefers the architecture-specific disk image for the running machine,
    /// then the universal one, then any disk image at all.
    static func preferredDMG(from assets: [ReleaseAsset], isAppleSilicon: Bool) -> ReleaseAsset? {
        let images = assets.filter(\.isDiskImage)
        let wanted = isAppleSilicon ? "arm64" : "intel"
        return images.first { $0.name.lowercased().contains(wanted) }
            ?? images.first { !$0.name.lowercased().contains("arm64") && !$0.name.lowercased().contains("intel") }
            ?? images.first
    }
}

/// A published GitHub release.
struct RemoteRelease: Sendable, Equatable {
    let tagName: String
    let name: String?
    let publishedAt: Date?
    let htmlURL: URL?
    let assets: [ReleaseAsset]

    var version: String {
        tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }
}

/// What the updater currently believes about this build versus the branch head.
enum UpdateStatus: Sendable, Equatable {
    /// No check has run yet in this session.
    case idle
    case checking
    /// This build is the branch head.
    case upToDate
    /// A newer commit exists on the branch.
    case updateAvailable(RemoteCommit)
    /// The build was stamped but its commit is not reachable from the branch head
    /// — a local or experimental build rather than an out-of-date one.
    case localRevisionUnknown(RemoteCommit)
    case failed(String)

    var remoteCommit: RemoteCommit? {
        switch self {
        case .updateAvailable(let commit), .localRevisionUnknown(let commit): return commit
        default: return nil
        }
    }

    var isUpdateAvailable: Bool {
        if case .updateAvailable = self { return true }
        return false
    }
}

/// How the running app should be replaced once a newer commit is chosen.
enum UpdateInstallMethod: String, Sendable, CaseIterable, Identifiable {
    /// Download the release disk image and swap the installed bundle in place.
    case diskImage
    /// `git pull` a source checkout and rebuild it.
    case sourceRebuild

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diskImage:     return L("update.method.dmg", "Install from release disk image")
        case .sourceRebuild: return L("update.method.source", "Pull and rebuild from source")
        }
    }
}

/// Progress of an in-flight installation.
enum UpdateInstallPhase: Sendable, Equatable {
    case idle
    case downloading(fraction: Double?)
    case verifying
    case installing
    case rebuilding
    case relaunching
    case finished
    case failed(String)

    var description: String {
        switch self {
        case .idle:                     return ""
        case .downloading(let fraction):
            guard let fraction else { return L("update.phase.downloading", "Downloading…") }
            return L("update.phase.downloading.percent", "Downloading… %d%%", Int(fraction * 100))
        case .verifying:                return L("update.phase.verifying", "Verifying download…")
        case .installing:               return L("update.phase.installing", "Installing…")
        case .rebuilding:               return L("update.phase.rebuilding", "Rebuilding from source…")
        case .relaunching:              return L("update.phase.relaunching", "Relaunching…")
        case .finished:                 return L("update.phase.finished", "Up to date")
        case .failed(let message):      return message
        }
    }

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .installing, .rebuilding, .relaunching: return true
        default: return false
        }
    }
}
