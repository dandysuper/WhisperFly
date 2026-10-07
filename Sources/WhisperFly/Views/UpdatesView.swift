import SwiftUI

/// Updates tab: what this build is, what the tracked branch holds, and the two
/// ways to move to a newer commit.
///
/// The updater compares **commits**, not version numbers. WhisperFly ships from
/// `master`, so a merged commit is the event that matters and the version string
/// in `Info.plist` lags behind it. That is why the local build is described by
/// its short SHA and why the remote side shows the branch tip rather than the
/// latest release tag.
struct UpdatesView: View {

    @ObservedObject var controller: AppController
    @ObservedObject var updates: UpdateService

    var body: some View {
        Form {
            Section(L("updates.build.header", "This Build")) {
                labelled(L("updates.build.version", "Version"), BuildInfo.displayVersion)
                labelled(L("updates.build.commit", "Commit"), updates.localRevisionDescription)
                if let commitDate = BuildInfo.commitDate {
                    labelled(L("updates.build.commit_date", "Committed"),
                             Self.dateFormatter.string(from: commitDate))
                }
                if let buildDate = BuildInfo.buildDate {
                    labelled(L("updates.build.built", "Built"),
                             Self.dateFormatter.string(from: buildDate))
                }
                if !BuildInfo.isAppBundle {
                    Text(L("updates.build.not_bundled",
                           "Running from a build directory rather than an installed .app, so the disk-image install method is unavailable."))
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(L("updates.remote.header", "Tracked Branch")) {
                labelled(L("updates.remote.repository", "Repository"), updates.configuration.repository)
                labelled(L("updates.remote.branch", "Branch"), updates.configuration.branch)
                statusRow

                if let commit = updates.status.remoteCommit {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commit.headline)
                            .font(.system(size: 11, weight: .medium))
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 4) {
                            Text(commit.shortSHA)
                                .font(.system(size: 10, design: .monospaced))
                            if let author = commit.authorName {
                                Text("·")
                                Text(author)
                            }
                            if let date = commit.authoredAt {
                                Text("·")
                                Text(Self.dateFormatter.string(from: date))
                            }
                        }
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    }
                }

                if !updates.phase.description.isEmpty {
                    Text(updates.phase.description)
                        .font(.caption)
                        .foregroundColor(updates.phase.isBusy ? .secondary : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button(L("updates.action.check", "Check Now")) {
                        controller.checkForUpdatesNow()
                    }
                    .disabled(updates.isBusy)

                    Button(L("updates.action.install", "Update Now")) {
                        controller.installUpdate(using: updates.preferredInstallMethod)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!updates.canInstall || updates.isBusy)

                    Button(L("updates.action.release_page", "Release Page")) {
                        updates.openReleasePage()
                    }
                }

                Text(installMethodExplanation)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(L("updates.source.header", "Source")) {
                TextField(L("updates.source.repository_field", "Owner/Repository"),
                          text: $controller.settings.updateRepository)
                    .textFieldStyle(.roundedBorder)
                TextField(L("updates.source.branch_field", "Branch"),
                          text: $controller.settings.updateBranch)
                    .textFieldStyle(.roundedBorder)
                SecureField(L("updates.source.token_field", "GitHub token (optional)"),
                            text: $controller.settings.updateToken)
                    .textFieldStyle(.roundedBorder)
                Text(L("updates.source.token_hint",
                       "Only needed to raise the API rate limit or to follow a private fork. A read-only token is enough."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(L("updates.source.auto", "Check automatically"),
                       isOn: $controller.settings.updateAutomaticallyChecks)
                if controller.settings.updateAutomaticallyChecks {
                    Stepper(
                        L("updates.source.interval", "Check every %d hours", controller.settings.updateCheckIntervalHours),
                        value: $controller.settings.updateCheckIntervalHours,
                        in: 1...72, step: 1
                    )
                }
            }

            Section(L("updates.checkout.header", "Source Checkout")) {
                TextField(L("updates.checkout.path", "Path to a git checkout"),
                          text: $controller.settings.updateSourceCheckoutPath)
                    .textFieldStyle(.roundedBorder)
                if let detected = updates.detectedCheckout {
                    Label(L("updates.checkout.detected", "Found: %@", detected.path),
                          systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .textSelection(.enabled)
                } else {
                    Text(L("updates.checkout.hint",
                           "Optional. Point this at a clone of the repository to enable updating by pulling and rebuilding, which works even when no release disk image has been published."))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: controller.settings) { _, _ in
            controller.saveSettings()
        }
    }

    // MARK: - Pieces

    private var statusRow: some View {
        HStack(spacing: 6) {
            switch updates.status {
            case .idle:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                Text(L("updates.status.idle", "Not checked yet"))
            case .checking:
                ProgressView()
                    .controlSize(.small)
                Text(L("updates.status.checking", "Checking…"))
            case .upToDate:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text(L("updates.status.up_to_date", "Up to date"))
            case .updateAvailable:
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)
                Text(L("updates.status.available", "A newer commit is available"))
            case .localRevisionUnknown:
                Image(systemName: "questionmark.circle.fill")
                    .foregroundColor(.orange)
                Text(L("updates.status.local_revision",
                       "This build's commit is not on the branch — a local or experimental build"))
            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.system(size: 11))
    }

    private var installMethodExplanation: String {
        switch updates.preferredInstallMethod {
        case .diskImage:
            return L("updates.method.dmg_explanation",
                     "Update Now downloads the newest release disk image, verifies it and replaces the installed app, then relaunches.")
        case .sourceRebuild:
            return L("updates.method.source_explanation",
                     "Update Now pulls the source checkout and rebuilds the app, then relaunches. This takes a few minutes.")
        }
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
