import AppKit
import SwiftUI

/// A borderless, non-activating panel. `canBecomeKey`/`canBecomeMain` are false
/// so showing it never pulls keyboard focus away from the app being controlled.
final class PillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating pill: builds it once, then re-sizes and re-centres it as
/// the text changes.
@MainActor
final class PillController {
    private var panel: PillPanel?
    private var hosting: NSHostingView<PillView>?

    private(set) var state: PillState = .idle
    private(set) var text: String = "Idle"
    private(set) var isLatched = false
    private(set) var isLive = false

    /// When false the pill stays hidden regardless of state.
    var isEnabled = true {
        didSet { isEnabled ? show() : hide() }
    }

    private var revertWorkItem: DispatchWorkItem?

    // MARK: - Public API

    /// Show a state. With `revertAfter`, fall back to idle after that many
    /// seconds — unless something newer was shown in the meantime.
    func set(
        _ state: PillState,
        _ text: String,
        isLatched: Bool = false,
        isLive: Bool = false,
        revertAfter: TimeInterval? = nil
    ) {
        revertWorkItem?.cancel()
        revertWorkItem = nil

        self.state = state
        self.text = text
        self.isLatched = isLatched
        self.isLive = isLive
        render()

        if let revertAfter {
            let work = DispatchWorkItem { [weak self] in
                self?.set(.idle, "Idle")
            }
            revertWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + revertAfter, execute: work)
        }
    }

    func show() {
        guard isEnabled else { return }
        build()
        render()
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    // MARK: - Internals

    private func build() {
        guard panel == nil else { return }

        let view = PillView(state: state, text: text, isLatched: isLatched, isLive: isLive)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 260, height: PillView.height)

        let p = PillPanel(
            contentRect: host.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = true
        p.isMovable = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = host

        panel = p
        hosting = host
    }

    private func render() {
        guard isEnabled else { return }
        build()
        guard let panel, let hosting else { return }

        hosting.rootView = PillView(state: state, text: text, isLatched: isLatched, isLive: isLive)
        hosting.layoutSubtreeIfNeeded()

        let width = min(max(hosting.fittingSize.width, PillView.minWidth), PillView.maxWidth)
        let height = PillView.height

        // Top-centre of the screen holding the cursor, just under the menu bar.
        let screen = screenUnderCursor() ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = visible.origin.x + (visible.width - width) / 2
        let y = visible.origin.y + visible.height - height - 8

        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        panel.orderFrontRegardless()
    }

    private func screenUnderCursor() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
