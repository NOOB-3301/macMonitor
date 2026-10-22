import AppKit
import CShims

public enum SessionFocus {
    public static func focus(_ session: RunningSession) {
        var chain: [Int32] = [session.pid]
        var buffer = [Int32](repeating: 0, count: 16)
        let count = Int(buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            mm_proc_ancestors(session.pid, pointer.baseAddress, Int32(pointer.count))
        })
        if count > 0 {
            chain.append(contentsOf: buffer[0..<count])
        }

        for pid in chain {
            guard let app = NSRunningApplication(processIdentifier: pid) else {
                continue
            }
            switch app.bundleIdentifier {
            case "com.microsoft.VSCode":
                focusVSCode(session)
                return
            case "com.apple.Terminal":
                app.activate(options: [])
                _ = focusTerminal(session)
                return
            case "com.googlecode.iterm2":
                app.activate(options: [])
                _ = focusITerm(session)
                return
            default:
                continue
            }
        }
    }

    private static func focusVSCode(_ session: RunningSession) {
        if openWithCodeCLI(session.cwd) { return }
        let workspace = NSWorkspace.shared
        if let app = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == "com.microsoft.VSCode"
        }) {
            app.activate(options: [])
            _ = raiseWindow(workspaceFolder: session.cwd)
        }
    }

    private static func openWithCodeCLI(_ folder: String) -> Bool {
        let home = NSHomeDirectory()
        let candidates = [
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            home + "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
        ]
        guard let cli = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0)
        }) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: cli)
        process.arguments = [folder]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private static func raiseWindow(workspaceFolder: String) -> Bool {
        let leaf = (workspaceFolder as NSString).lastPathComponent
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Visual Studio Code" to activate
        delay 0.3
        tell application "System Events"
            tell process "Code"
                set matches to windows whose name contains "\(leaf)"
                if count of matches > 0 then
                    perform action "AXRaise" of item 1 of matches
                end if
            end tell
        end tell
        """
        return NSAppleScript(source: script)?.executeAndReturnError(nil) != nil
    }

    private static func appleScript(_ source: String) -> Bool {
        NSAppleScript(source: source)?.executeAndReturnError(nil) != nil
    }

    private static func focusTerminal(_ session: RunningSession) -> Bool {
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(session.tty)" then
                        set selected tab of w to t
                        set index of w to 1
                        return
                    end if
                end repeat
            end repeat
        end tell
        """
        return appleScript(script)
    }

    private static func focusITerm(_ session: RunningSession) -> Bool {
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(session.tty)" then
                            select s
                            return
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        """
        return appleScript(script)
    }
}
