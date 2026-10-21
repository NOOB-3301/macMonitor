import Foundation

public enum Paths {
    public static var appSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("macmon", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var claudeCache: URL {
        appSupport.appendingPathComponent("claude.json")
    }

    public static var jsonlState: URL {
        appSupport.appendingPathComponent("jsonl-state.json")
    }

    public static var claudeProjects: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects")
    }
}
