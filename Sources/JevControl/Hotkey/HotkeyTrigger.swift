import CoreGraphics
import Foundation

/// The key you hold to talk.
///
/// Modifier triggers are preferred: they already emit a clean press and release
/// (`flagsChanged`), so nothing about the system keyboard has to be modified.
/// Caps Lock is the exception — it is a latching toggle, not a key, so it only
/// works by remapping it to F18 at the HID layer, which is a system-wide change
/// that outlives the app.
enum HotkeyTrigger: String, CaseIterable, Identifiable {
    case leftOption
    case rightOption
    case capsLock

    static let `default`: HotkeyTrigger = .leftOption

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftOption: return "Left Option (⌥)"
        case .rightOption: return "Right Option (⌥)"
        case .capsLock: return "Caps Lock"
        }
    }

    var detail: String {
        switch self {
        case .leftOption:
            return "Nothing to install. Option on its own types nothing, and Jev hides it while you hold it."
        case .rightOption:
            return "Same, but on the right. Pick this if you hold ⌥ with your left hand for shortcuts."
        case .capsLock:
            return "Frees both ⌥ keys, but needs a system-wide hidutil remap to F18 that outlives the app."
        }
    }

    /// macOS virtual keycodes. 58/61 are the two Option keys; 79 is F18, which
    /// no physical Mac keyboard has — the point of remapping Caps Lock onto it.
    var keyCode: Int64 {
        switch self {
        case .leftOption: return 58
        case .rightOption: return 61
        case .capsLock: return 79
        }
    }

    /// Modifiers report through `flagsChanged`, ordinary keys through key events.
    var isModifier: Bool { self != .capsLock }

    /// Only Caps Lock needs the hidutil mapping.
    var needsCapsLockRemap: Bool { self == .capsLock }

    /// Device-dependent flag bit, the only reliable way to tell the left
    /// Option key from the right one — `maskAlternate` is set by both.
    /// From `IOKit/hidsystem/IOLLEvent.h`: NX_DEVICELALTKEYMASK / NX_DEVICERALTKEYMASK.
    var deviceFlagMask: UInt64 {
        switch self {
        case .leftOption: return 0x20
        case .rightOption: return 0x40
        case .capsLock: return 0
        }
    }

    static let anyOptionDeviceMask: UInt64 = 0x20 | 0x40
}
