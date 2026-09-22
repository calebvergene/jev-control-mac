import AppKit
import SwiftUI

@main
struct JevControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(state: state, delegate: delegate)
        } label: {
            Image(systemName: state.isListening ? "mic.fill" : "mic")
        }
    }
}

private struct MenuBarContent: View {
    @ObservedObject var state: AppState
    let delegate: AppDelegate

    var body: some View {
        Text(statusLine)

        Divider()

        Button("Setup…") { delegate.showOnboarding() }
        if state.needsRelaunch {
            Button("Relaunch to pick up permissions") { state.relaunch() }
        }
        Toggle("Show pill", isOn: $state.showPill)
        Toggle("Sounds", isOn: $state.playSounds)

        Divider()

        Picker("Push-to-talk key", selection: $state.trigger) {
            ForEach(HotkeyTrigger.allCases) { Text($0.title).tag($0) }
        }

        if state.remapActive {
            Button("Restore Caps Lock") { state.removeRemap() }
        }

        Divider()

        Button("Quit Jev Control") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusLine: String {
        if state.needsRelaunch { return "Relaunch needed" }
        if !state.isTapActive { return "Waiting for permissions" }
        if state.needsRemap { return "Caps Lock not remapped" }
        if state.isListening { return state.isLatched ? "Listening (latched)" : "Listening" }
        return "Ready — hold \(state.trigger.title)"
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt and braces alongside LSUIElement: no Dock icon, never activates
        // on its own, so the app being controlled keeps keyboard focus.
        NSApp.setActivationPolicy(.accessory)

        let state = AppState.shared
        state.start()

        // First run, or a revoked permission: show the checklist.
        if !state.permissions.requiredAreGranted || state.needsRemap {
            showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutDown()
    }

    func showOnboarding() {
        onboarding.show(state: AppState.shared)
    }
}
