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

        let view = PillView(state: state, text: text, isLatched: isLatched,
                            isLive: isLive, width: 260, isMultiline: false)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 260, height: PillView.lineHeight)

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

        let screen = screenUnderCursor() ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = min(PillView.maxWidth, visible.width * 0.7)

        let layout = layout(for: text, maxWidth: maxWidth)

        hosting.rootView = PillView(
            state: state,
            text: layout.text,
            isLatched: isLatched,
            isLive: isLive,
            width: layout.width,
            isMultiline: layout.isMultiline
        )
        hosting.layoutSubtreeIfNeeded()

        // Top-centre of the screen holding the cursor, just under the menu bar.
        let x = visible.origin.x + (visible.width - layout.width) / 2
        let y = visible.origin.y + visible.height - layout.height - 8

        panel.setFrame(
            NSRect(x: x, y: y, width: layout.width, height: layout.height),
            display: true
        )
        hosting.frame = NSRect(x: 0, y: 0, width: layout.width, height: layout.height)
        panel.orderFrontRegardless()
    }

    // MARK: - Measurement

    private struct Layout {
        var text: String
        var width: CGFloat
        var height: CGFloat
        var isMultiline: Bool
    }

    private static let font = NSFont.systemFont(ofSize: 13.5, weight: .medium)

    /// Decides the pill's shape from the text itself.
    ///
    /// SwiftUI is not asked to size this. An earlier version let the text keep
    /// its ideal width and clamped the window afterwards, which silently
    /// clipped the end of every long transcript — the half that matters while
    /// you are still speaking.
    private func layout(for text: String, maxWidth: CGFloat) -> Layout {
        let oneLineTextWidth = PillView.textWidth(in: maxWidth, isLatched: isLatched)
        let measured = ceil(size(of: text, width: .greatestFiniteMagnitude).width)

        if measured <= oneLineTextWidth {
            let chrome = maxWidth - oneLineTextWidth
            let width = min(max(measured + chrome, PillView.minWidth), maxWidth)
            return Layout(text: text, width: width, height: PillView.lineHeight, isMultiline: false)
        }

        // Wraps: fixed at the maximum width, growing downward.
        let lineHeight = ceil(size(of: "M", width: oneLineTextWidth).height)
        let maxTextHeight = lineHeight * CGFloat(PillView.maxLines)
        let fitted = dropLeadingWords(from: text, width: oneLineTextWidth, maxHeight: maxTextHeight)
        let textHeight = ceil(size(of: fitted, width: oneLineTextWidth).height)

        return Layout(
            text: fitted,
            width: maxWidth,
            height: textHeight + PillView.verticalPadding * 2,
            isMultiline: true
        )
    }

    /// Trims from the front, so the newest words survive. The opposite of what
    /// a normal truncation does, and the right way round for a live transcript.
    private func dropLeadingWords(from text: String, width: CGFloat, maxHeight: CGFloat) -> String {
        var candidate = text
        var guardCount = 0

        while ceil(size(of: candidate, width: width).height) > maxHeight, guardCount < 500 {
            guardCount += 1
            let body = candidate.hasPrefix("… ") ? String(candidate.dropFirst(2)) : candidate
            guard let space = body.firstIndex(of: " ") else { break }
            candidate = "… " + body[body.index(after: space)...]
        }
        return candidate
    }

    private func size(of text: String, width: CGFloat) -> CGSize {
        let attributed = NSAttributedString(string: text, attributes: [.font: Self.font])
        return attributed.boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        ).size
    }

    private func screenUnderCursor() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }
}
