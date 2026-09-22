import CoreGraphics
import Foundation

/// Synthetic keyboard and scroll input.
///
/// `CGEvent` rather than AppleScript's `System Events`: no subprocess per
/// keystroke, no Automation permission prompt, and Unicode goes through
/// directly instead of being escaped into a script string.
enum Keyboard {
    /// Named shortcuts. The key set matches what `Brain` offers Jev, so a
    /// choice always maps to something executable.
    enum Shortcut: String, CaseIterable {
        case enterKey = "enter"
        case escape, tab, space, backspace
        case arrowUp = "arrow_up", arrowDown = "arrow_down"
        case arrowLeft = "arrow_left", arrowRight = "arrow_right"
        case copy, paste, cut, undo, redo
        case selectAll = "select_all"
        case save, find, new
        case newTab = "new_tab"
        case closeTabOrWindow = "close_tab_or_window"
        case reopenClosedTab = "reopen_closed_tab"
        case quitApp = "quit_app"
        case minimizeWindow = "minimize_window"
        case hideApp = "hide_app"
        case fullscreen
        case nextTab = "next_tab", previousTab = "previous_tab"
        case browserBack = "browser_back", browserForward = "browser_forward"
        case reload
        case addressBar = "address_bar"
        case spotlight
        case switchApp = "switch_app"
        case nextWindow = "next_window"
        case deleteWord = "delete_word", deleteLine = "delete_line"
        case zoomIn = "zoom_in", zoomOut = "zoom_out"
        case bold, italic
        case sendMessage = "send_message"
        case emojiPicker = "emoji_picker"
        case showDesktop = "show_desktop"
        case lockScreen = "lock_screen"

        var keyCode: CGKeyCode {
            switch self {
            case .enterKey, .sendMessage: return 36
            case .escape: return 53
            case .tab, .nextTab, .previousTab, .switchApp: return 48
            case .space, .spotlight, .emojiPicker: return 49
            case .backspace, .deleteWord, .deleteLine: return 51
            case .arrowUp: return 126
            case .arrowDown: return 125
            case .arrowLeft: return 123
            case .arrowRight: return 124
            case .copy: return 8          // c
            case .paste: return 9         // v
            case .cut: return 7           // x
            case .undo, .redo: return 6   // z
            case .selectAll: return 0     // a
            case .save: return 1          // s
            case .find, .fullscreen: return 3  // f
            case .new: return 45          // n
            case .newTab, .reopenClosedTab: return 17  // t
            case .closeTabOrWindow: return 13          // w
            case .quitApp, .lockScreen: return 12      // q
            case .minimizeWindow: return 46            // m
            case .hideApp: return 4                    // h
            case .browserBack: return 33               // [
            case .browserForward: return 30            // ]
            case .reload: return 15                    // r
            case .addressBar: return 37                // l
            case .nextWindow: return 50                // `
            case .zoomIn: return 24                    // =
            case .zoomOut: return 27                   // -
            case .bold: return 11                      // b
            case .italic: return 34                    // i
            case .showDesktop: return 103              // F11
            }
        }

        var flags: CGEventFlags {
            switch self {
            case .enterKey, .escape, .tab, .space, .backspace,
                 .arrowUp, .arrowDown, .arrowLeft, .arrowRight, .showDesktop:
                return []
            case .redo:
                return [.maskCommand, .maskShift]
            case .reopenClosedTab:
                return [.maskCommand, .maskShift]
            case .previousTab:
                return [.maskControl, .maskShift]
            case .nextTab:
                return [.maskControl]
            case .fullscreen:
                return [.maskCommand, .maskControl]
            case .emojiPicker:
                return [.maskCommand, .maskControl]
            case .lockScreen:
                return [.maskCommand, .maskControl]
            case .deleteWord:
                return [.maskAlternate]
            default:
                return [.maskCommand]
            }
        }
    }

    private static var source: CGEventSource? {
        CGEventSource(stateID: .combinedSessionState)
    }

    static func press(_ shortcut: Shortcut, times: Int = 1) {
        for _ in 0..<max(1, times) {
            post(keyCode: shortcut.keyCode, flags: shortcut.flags)
        }
    }

    static func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = source
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Types a string as Unicode, so emoji and accents work without depending
    /// on the current keyboard layout.
    static func type(_ text: String) {
        guard !text.isEmpty else { return }
        let source = source

        // keyboardSetUnicodeString is capped per event; 16 UTF-16 units is
        // comfortably inside it and keeps the typing visibly smooth.
        for chunk in Array(text.utf16).chunked(into: 16) {
            var units = chunk
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { continue }
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            usleep(1500)
        }
    }

    /// Real scroll-wheel events, so they work in any scrollable view rather
    /// than only where arrow keys happen to scroll.
    static func scroll(direction: String, amount: String) {
        if direction == "top" || direction == "bottom" {
            post(keyCode: direction == "top" ? 126 : 125, flags: [.maskCommand])
            return
        }
        let lines: Int
        switch amount {
        case "little": lines = 5
        case "a_lot": lines = 40
        default: lines = 15
        }
        let sign: Int32 = direction == "up" ? 1 : -1
        for _ in 0..<lines {
            guard let event = CGEvent(
                scrollWheelEvent2Source: source,
                units: .line,
                wheelCount: 1,
                wheel1: sign * 3, wheel2: 0, wheel3: 0
            ) else { continue }
            event.post(tap: .cghidEventTap)
            usleep(4000)
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
