import AppKit

public enum SessionFocus {
    public static func focus(_ session: RunningSession) {
        let workspace = NSWorkspace.shared
        let terminalRunning = workspace.runningApplications.contains {
            $0.bundleIdentifier == "com.apple.Terminal"
        }
        let itermRunning = workspace.runningApplications.contains {
            $0.bundleIdentifier == "com.googlecode.iterm2"
        }

        if itermRunning, focusITerm(session) { return }
        if terminalRunning, focusTerminal(session) { return }
        let cwdURL = URL(fileURLWithPath: session.cwd)
        NSWorkspace.shared.open(cwdURL)
    }

    private static func appleScript(_ source: String) -> Bool {
        let descriptor = NSAppleScript(source: source)?
            .executeAndReturnError(nil)
        return descriptor != nil
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
