import Foundation

/// Caps Lock → F18, via `hidutil`.
///
/// Caps Lock is a latching modifier: the OS reports a state change, not a
/// press and a release, so it cannot drive push-to-talk directly. Remapping it
/// at the HID layer to F18 — a key no Mac keyboard has and no app binds —
/// turns it into an ordinary key with a clean down/up pair.
///
/// `hidutil` mappings die on reboot and on some sleep/wake cycles, so the same
/// command is persisted as a LaunchAgent.
enum CapsLockRemap {
    /// HID usage IDs. 0x700000039 = Caps Lock, 0x70000006D = F18.
    static let capsLockUsage: UInt64 = 0x700000039
    static let f18Usage: UInt64 = 0x70000006D

    static let launchAgentLabel = "ai.jev.control.capslock"

    static var mappingJSON: String {
        "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":\(capsLockUsage),"
            + "\"HIDKeyboardModifierMappingDst\":\(f18Usage)}]}"
    }

    static var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist")
    }

    // MARK: - Status

    /// True when the mapping is live in the HID layer right now.
    static func isActive() -> Bool {
        guard let out = run("/usr/bin/hidutil", ["property", "--get", "UserKeyMapping"]).stdout else {
            return false
        }
        return out.contains("\(f18Usage)") && out.contains("\(capsLockUsage)")
    }

    /// True when the LaunchAgent that re-applies it at login is installed.
    static func isPersisted() -> Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    // MARK: - Install / remove

    @discardableResult
    static func install() -> Result<Void, RemapError> {
        let set = run("/usr/bin/hidutil", ["property", "--set", mappingJSON])
        guard set.status == 0 else {
            return .failure(.hidutilFailed(set.stderr ?? "hidutil exited \(set.status)"))
        }

        do {
            try FileManager.default.createDirectory(
                at: launchAgentURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try launchAgentPlist().write(to: launchAgentURL, atomically: true, encoding: .utf8)
        } catch {
            return .failure(.plistFailed(error.localizedDescription))
        }

        let domain = "gui/\(getuid())"
        _ = run("/bin/launchctl", ["bootout", "\(domain)/\(launchAgentLabel)"])
        let boot = run("/bin/launchctl", ["bootstrap", domain, launchAgentURL.path])
        guard boot.status == 0 else {
            // The remap itself worked; only persistence failed.
            return .failure(.launchctlFailed(boot.stderr ?? "launchctl exited \(boot.status)"))
        }
        return .success(())
    }

    @discardableResult
    static func remove() -> Result<Void, RemapError> {
        let clear = run("/usr/bin/hidutil", ["property", "--set", "{\"UserKeyMapping\":[]}"])
        _ = run("/bin/launchctl", ["bootout", "gui/\(getuid())/\(launchAgentLabel)"])
        try? FileManager.default.removeItem(at: launchAgentURL)
        guard clear.status == 0 else {
            return .failure(.hidutilFailed(clear.stderr ?? "hidutil exited \(clear.status)"))
        }
        return .success(())
    }

    private static func launchAgentPlist() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key><string>\(launchAgentLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>/usr/bin/hidutil</string>
                <string>property</string>
                <string>--set</string>
                <string>\(mappingJSON)</string>
            </array>
            <key>RunAtLoad</key><true/>
        </dict>
        </plist>
        """
    }

    // MARK: - Process helper

    private static func run(_ path: String, _ args: [String]) -> (status: Int32, stdout: String?, stderr: String?) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = args
        let out = Pipe(), err = Pipe()
        task.standardOutput = out
        task.standardError = err
        do {
            try task.run()
        } catch {
            return (-1, nil, error.localizedDescription)
        }
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return (task.terminationStatus,
                String(data: outData, encoding: .utf8),
                String(data: errData, encoding: .utf8))
    }

    enum RemapError: LocalizedError {
        case hidutilFailed(String)
        case plistFailed(String)
        case launchctlFailed(String)

        var errorDescription: String? {
            switch self {
            case .hidutilFailed(let m): return "hidutil failed: \(m)"
            case .plistFailed(let m): return "Could not write the LaunchAgent: \(m)"
            case .launchctlFailed(let m):
                return "Remap applied, but it will not survive a reboot: \(m)"
            }
        }
    }
}
