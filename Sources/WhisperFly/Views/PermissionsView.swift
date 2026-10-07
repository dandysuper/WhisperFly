import SwiftUI

/// Permissions tab: the state of all three TCC grants, why they behave the way
/// they do, and the one-click repair for the case the UI otherwise cannot fix.
struct PermissionsView: View {

    @ObservedObject var controller: AppController
    @ObservedObject var permissions: PermissionService
    /// Set only when a reset could not complete — the app stays running so the
    /// user can read the reason instead of being relaunched pointlessly.
    @StateObject private var repairError = LocalState<String?>(nil)

    var body: some View {
        Form {
            Section {
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(
                        kind: kind,
                        state: permissions.state(for: kind),
                        onRequest: { controller.requestPermission(kind) },
                        onOpenSettings: { permissions.openSettings(for: kind) },
                        onRefresh: { Task { await permissions.refresh(kind) } }
                    )
                }
            } header: {
                Text(L("settings.permissions.header", "Required Permissions"))
            } footer: {
                Text(L("settings.permissions.footer",
                       "WhisperFly asks macOS for each of these the first time it needs them."))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Section(L("settings.signature.header", "Code Signature")) {
                signatureDetails

                if let warning = permissions.signatureWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Label(
                        L("settings.signature.stable",
                          "Signed so macOS recognises future versions as the same app."),
                        systemImage: "checkmark.seal.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.green)
                }
            }

            Section(L("settings.permissions.repair.header", "Reset Permissions")) {
                Text(L("settings.permissions.repair.body",
                       "Use this if System Settings shows a permission as enabled but WhisperFly still cannot use it — usually after the app was signed differently. WhisperFly will quit and reopen."))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button(L("settings.permissions.repair.button", "Reset and Relaunch")) {
                        repairError.value = controller.repairPermissionsAndRelaunch()
                    }

                    Button(L("settings.permissions.recheck", "Check Again")) {
                        Task { await permissions.refreshAll() }
                    }
                }

                if let message = repairError.value {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task { await permissions.refreshAll() }
        }
    }

    // MARK: - Signature details

    private var signatureDetails: some View {
        VStack(alignment: .leading, spacing: 3) {
            detailRow(
                L("settings.signature.team", "Team identifier"),
                permissions.signature.teamIdentifier ?? L("settings.signature.none", "none")
            )
            detailRow(
                L("settings.signature.adhoc", "Ad-hoc signed"),
                permissions.signature.isAdHoc ? L("common.yes", "Yes") : L("common.no", "No")
            )
            detailRow(
                L("settings.signature.hardened", "Hardened runtime"),
                permissions.signature.hasHardenedRuntime ? L("common.yes", "Yes") : L("common.no", "No")
            )
            if let identifier = permissions.signature.identifier {
                detailRow(L("settings.signature.identifier", "Signature identifier"), identifier)
            }
            if let requirement = permissions.signature.designatedRequirement {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("settings.signature.requirement", "Designated requirement"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(requirement)
                        .font(.system(size: 9, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
