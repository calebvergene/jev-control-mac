import AVFoundation
import AppKit
import ApplicationServices
import CoreGraphics
import IOKit.hid

/// The four TCC permissions Jev Control needs.
///
/// macOS attributes these to the *signed bundle*, so they only show up under
/// "Jev Control" in System Settings once the app runs from a real `.app` bundle
/// (see `Scripts/build.sh`). Running the raw SwiftPM binary attributes them to
/// the terminal instead — which is what jev-voice had to live with.
enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility
    case inputMonitoring
    case microphone
    case screenRecording

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        case .microphone: return "Microphone"
        case .screenRecording: return "Screen Recording"
        }
    }

    var why: String {
        switch self {
        case .accessibility: return "Read the focused window and drive controls."
        case .inputMonitoring: return "See the Caps Lock key without the focused app seeing it."
        case .microphone: return "Hear what you say while the key is held."
        case .screenRecording: return "Fallback for apps with no usable element tree."
        }
    }

    /// Screen Recording is not used until the vision fallback lands; the other
    /// three gate the hotkey and the mic.
    var isRequired: Bool { self != .screenRecording }

    /// Whether the system prompt can actually grant the permission.
    ///
    /// Microphone and Screen Recording show a real Allow / Don't Allow dialog,
    /// so prompting is worth it. Accessibility and Input Monitoring show a
    /// dialog whose only useful button opens System Settings — it cannot grant
    /// anything — so prompting just adds a click on the way there.
    var promptCanGrant: Bool {
        self == .microphone || self == .screenRecording
    }

    /// Deep link into the matching System Settings pane.
    var settingsURL: URL {
        let pane: String
        switch self {
        case .accessibility: pane = "Privacy_Accessibility"
        case .inputMonitoring: pane = "Privacy_ListenEvent"
        case .microphone: pane = "Privacy_Microphone"
        case .screenRecording: pane = "Privacy_ScreenCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }
}

enum PermissionState {
    case granted
    case denied
    case notDetermined

    var isGranted: Bool { self == .granted }
}

struct PermissionSnapshot {
    var states: [PermissionKind: PermissionState] = [:]

    subscript(kind: PermissionKind) -> PermissionState {
        states[kind] ?? .notDetermined
    }

    var requiredAreGranted: Bool {
        PermissionKind.allCases.filter(\.isRequired).allSatisfy { self[$0].isGranted }
    }

    var allAreGranted: Bool {
        PermissionKind.allCases.allSatisfy { self[$0].isGranted }
    }
}

enum Permissions {
    static func snapshot() -> PermissionSnapshot {
        var snap = PermissionSnapshot()
        for kind in PermissionKind.allCases {
            snap.states[kind] = check(kind)
        }
        return snap
    }

    static func check(_ kind: PermissionKind) -> PermissionState {
        switch kind {
        case .accessibility:
            // AX has no "denied" signal — an untrusted process looks the same
            // whether the user said no or was never asked.
            return AXIsProcessTrusted() ? .granted : .notDetermined

        case .inputMonitoring:
            switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
            case kIOHIDAccessTypeGranted: return .granted
            case kIOHIDAccessTypeDenied: return .denied
            default: return .notDetermined
            }

        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .denied, .restricted: return .denied
            default: return .notDetermined
            }

        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        }
    }

    /// Ask for a permission in whichever way actually gets the user closer to
    /// having it: a real system dialog where one exists, System Settings
    /// otherwise. Once a permission has been decided, macOS shows nothing — so
    /// callers should fall back to `openSettings` on a `denied`.
    static func request(_ kind: PermissionKind, completion: (() -> Void)? = nil) {
        guard kind.promptCanGrant else {
            openSettings(kind)
            completion?()
            return
        }

        switch kind {
        case .accessibility, .inputMonitoring:
            // Unreachable: both are handled above.
            completion?()

        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { completion?() }
            }

        case .screenRecording:
            DispatchQueue.global(qos: .userInitiated).async {
                _ = CGRequestScreenCaptureAccess()
                DispatchQueue.main.async { completion?() }
            }
        }
    }

    static func openSettings(_ kind: PermissionKind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }
}
