import SwiftUI

/// Setup checklist: the four TCC permissions, then the Caps Lock remap.
struct OnboardingView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Jev Control").font(.title2.weight(.semibold))
                Text("Hold Caps Lock to talk to your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Permissions").font(.headline)
                ForEach(PermissionKind.allCases) { kind in
                    PermissionRow(kind: kind, state: state.permissions[kind]) {
                        state.request(kind)
                    } openSettings: {
                        Permissions.openSettings(kind)
                    }
                }
                Text("macOS attributes these to the app bundle. If you rebuild Jev Control, "
                     + "macOS sees a new signature and you may have to re-tick the boxes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Caps Lock").font(.headline)
                Text("Caps Lock latches rather than pressing, so it can't drive push-to-talk. "
                     + "Jev remaps it to F18 — a key nothing else uses — with hidutil.")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    StatusDot(ok: state.remapActive)
                    Text(state.remapActive ? "Caps Lock → F18 is active" : "Caps Lock is unchanged")
                    Spacer()
                    if state.remapActive {
                        Button("Undo") { state.removeRemap() }
                    } else {
                        Button("Remap Caps Lock") { state.installRemap() }
                            .buttonStyle(.borderedProminent)
                    }
                }

                if state.remapActive && !state.remapPersisted {
                    Label("Will not survive a reboot — the LaunchAgent is missing.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Divider()

            HStack(spacing: 10) {
                StatusDot(ok: state.isTapActive)
                Text(state.isTapActive
                     ? "Key tap installed — hold Caps Lock to test."
                     : "Key tap refused. Grant Accessibility and Input Monitoring.")
                    .font(.callout)
                Spacer()
            }

            if let error = state.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear { state.refresh() }
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    let request: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StatusDot(ok: state.isGranted)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(kind.title)
                    if !kind.isRequired {
                        Text("optional").font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.18)))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(kind.why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if state.isGranted {
                Text("Granted").font(.caption).foregroundStyle(.secondary)
            } else {
                Button(state == .denied ? "Open Settings" : "Grant") {
                    state == .denied ? openSettings() : request()
                }
            }
        }
    }
}

private struct StatusDot: View {
    let ok: Bool
    var body: some View {
        Circle()
            .fill(ok ? Color.green : Color.secondary.opacity(0.45))
            .frame(width: 9, height: 9)
    }
}
