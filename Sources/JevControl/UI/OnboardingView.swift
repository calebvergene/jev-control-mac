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
                if state.needsRelaunch {
                    HStack(spacing: 8) {
                        Label("Granted, but this process is still seeing the old answer.",
                              systemImage: "arrow.clockwise.circle")
                            .font(.caption)
                        Spacer()
                        Button("Relaunch") { state.relaunch() }
                            .controlSize(.small)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.15)))
                }

                Text("Accessibility and Input Monitoring open straight to their pane — "
                     + "tick Jev Control there. If it is not listed, add it with + from "
                     + "Applications.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Push-to-talk key").font(.headline)

                Picker("", selection: $state.trigger) {
                    ForEach(HotkeyTrigger.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Text(state.trigger.detail)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.trigger.needsCapsLockRemap {
                    CapsLockRemapSection(state: state)
                } else if state.remapActive {
                    HStack(spacing: 8) {
                        Label("Caps Lock is still remapped to F18 from an earlier run.",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restore") { state.removeRemap() }
                            .controlSize(.small)
                    }
                }
            }

            Divider()

            HStack(spacing: 10) {
                StatusDot(ok: state.isTapActive)
                Text(state.isTapActive
                     ? "Key tap installed — hold \(state.trigger.title) to test."
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

/// Only shown when Caps Lock is the chosen trigger — it is the one key that
/// cannot work without modifying the system.
private struct CapsLockRemapSection: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
        .padding(.top, 2)
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
                Button(kind.promptCanGrant && state != .denied ? "Grant" : "Open Settings") {
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
