import SwiftUI

/// One permission, rendered the same way everywhere it appears.
///
/// The row is the only place that decides which action a permission state
/// deserves, so the menu bar and the settings tab can never disagree about what
/// the user should do next:
///
/// - `.notDetermined` → offer the in-app request, which raises the system prompt.
/// - `.denied` / `.restricted` → send the user to the pane that owns the switch;
///   a `restricted` state additionally explains that a policy, not the user, is
///   blocking it, so the button is hidden rather than shown uselessly.
/// - `.unknown` → offer a re-probe, because the probe simply could not answer.
struct PermissionRow: View {

    let kind: PermissionKind
    let state: PermissionState
    var isCompact: Bool = false
    let onRequest: () -> Void
    let onOpenSettings: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        if isCompact {
            compactRow
        } else {
            fullRow
        }
    }

    // MARK: - Full

    private var fullRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 15))
                .foregroundColor(state.tint)
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kind.title)
                        .font(.system(size: 12, weight: .medium))
                    stateBadge
                }
                Text(kind.purpose)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if kind.requiresRelaunchToTakeEffect, state == .granted {
                    Text(L("permission.relaunch_required",
                           "Granted. WhisperFly has to restart before this takes effect."))
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }

            Spacer(minLength: 8)

            actionButton
        }
        .padding(.vertical, 4)
    }

    // MARK: - Compact (menu bar)

    private var compactRow: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 11))
                .foregroundColor(state.tint)
            Text(kind.title)
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 4)
            actionButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(state.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Pieces

    private var stateBadge: some View {
        Text(state.label)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(state.tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(state.tint.opacity(0.15))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var actionButton: some View {
        switch state {
        case .granted:
            EmptyView()

        case .notDetermined:
            Button(L("permission.request", "Enable")) { onRequest() }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .tint(state.tint)

        case .denied:
            Button(L("permission.open_settings", "Open Settings")) { onOpenSettings() }
                .font(.caption)
                .buttonStyle(.borderedProminent)
                .tint(state.tint)

        case .restricted:
            // No button: only an administrator or MDM profile can change this.
            Text(L("permission.managed", "Managed"))
                .font(.caption2)
                .foregroundColor(.secondary)

        case .unknown:
            Button(L("permission.recheck", "Check Again")) { onRefresh() }
                .font(.caption)
                .buttonStyle(.bordered)
        }
    }
}

extension PermissionState {

    /// Colour used for the icon and badge of a permission in this state.
    var tint: Color {
        switch self {
        case .granted:       return .green
        case .notDetermined: return .orange
        case .denied:        return .red
        case .restricted:    return .red
        case .unknown:       return .secondary
        }
    }
}
