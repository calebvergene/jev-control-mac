import AppKit
import SwiftUI

/// A plain `NSWindow` rather than a SwiftUI `Window` scene: an accessory app has
/// no activation of its own, so the window has to be shown and focused by hand.
@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(state: AppState) {
        if window == nil {
            let hosting = NSHostingView(rootView: OnboardingView(state: state))
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Jev Control Setup"
            w.contentView = hosting
            w.isReleasedWhenClosed = false
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}


/// Host for the decision log.
@MainActor
final class DebugWindowController: NSObject {
    private var window: NSWindow?

    func show(log: DecisionLog) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 460),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Jev Control Decisions"
            w.contentView = NSHostingView(rootView: DebugView(log: log))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
