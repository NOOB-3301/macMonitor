import CShims
import Foundation

public enum SessionKind: String, Sendable {
    case claude
    case opencode

    var label: String {
        switch self {
        case .claude: return "claude"
        case .opencode: return "oc"
        }
    }
}

public struct RunningSession: Sendable, Equatable {
    public let kind: SessionKind
    public let pid: Int32
    public let cwd: String
    public let tty: String
    public let sessionID: String?
    public let directory: String?
    public let title: String?

    public init(kind: SessionKind, pid: Int32, cwd: String, tty: String,
                sessionID: String? = nil, directory: String? = nil,
                title: String? = nil) {
        self.kind = kind
        self.pid = pid
        self.cwd = cwd
        self.tty = tty
        self.sessionID = sessionID
        self.directory = directory
        self.title = title
    }
}

public final class SessionScanner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.arkab.macmon.sessions",
                                      qos: .utility)
    private var cache: [RunningSession]?
    private var cacheAt = Date.distantPast
    private let cacheLife: TimeInterval = 2
    private let dbPath: String

    public init(dbPath: String? = nil) {
        let home = NSHomeDirectory()
        self.dbPath = dbPath
            ?? home + "/.local/share/opencode/opencode.db"
    }

    public func sessions(completion: @escaping ([RunningSession]) -> Void) {
        let now = Date()
        if let cache, now.timeIntervalSince(cacheAt) < cacheLife {
            completion(cache)
            return
        }
        queue.async { [weak self] in
            guard let self else { return }
            let scanned = Self.scan(self.dbPath)
            self.cache = scanned
            self.cacheAt = Date()
            DispatchQueue.main.async {
                completion(scanned)
            }
        }
    }

    static func scan(_ dbPath: String) -> [RunningSession] {
        let maxProcs = 64
        var procs = [mm_proc_session](repeating: mm_proc_session(), count: maxProcs)
        let count = Int(procs.withUnsafeMutableBufferPointer { buffer -> Int32 in
            mm_session_procs(buffer.baseAddress, Int32(maxProcs))
        })
        guard count > 0 else { return [] }

        var pending: [RunningSession] = []
        var ids: [String] = []
        var indexByID: [String: Int] = [:]

        for i in 0..<count {
            let p = procs[i]
            let kind: SessionKind
            switch Self.fieldString(p.name) {
            case "claude": kind = .claude
            case "opencode": kind = .opencode
            default: continue
            }
            let argv = Self.fieldString(p.argv)
            let id = Self.sessionID(in: argv)
            let tty = Self.fieldString(p.tty)
            guard p.tty_valid != 0, !tty.isEmpty else { continue }
            let cwd = Self.fieldString(p.cwd)
            guard !cwd.isEmpty else { continue }

            let session = RunningSession(kind: kind, pid: p.pid, cwd: cwd,
                                         tty: tty, sessionID: id,
                                         directory: nil, title: nil)
            pending.append(session)
            if let id {
                indexByID[id] = pending.count - 1
                ids.append(id)
            }
        }

        guard !pending.isEmpty else { return [] }

        if !ids.isEmpty {
            var rows = [mm_db_session](repeating: mm_db_session(), count: ids.count)
            var errorBuffer = [CChar](repeating: 0, count: 256)
            var pointers = [UnsafePointer<CChar>?]()
            var buffers = [UnsafeMutablePointer<CChar>]()
            for id in ids {
                let buffer = strdup(id)!
                buffers.append(buffer)
                pointers.append(UnsafePointer(buffer))
            }
            defer { buffers.forEach { free($0) } }
            let rowCount = rows.count
            let rowCount32 = Int32(rowCount)
            let status = rows.withUnsafeMutableBufferPointer { rowBuffer -> Int32 in
                errorBuffer.withUnsafeMutableBufferPointer { errBuffer in
                    pointers.withUnsafeMutableBufferPointer { ptrBuffer in
                        mm_db_sessions(dbPath,
                                       ptrBuffer.baseAddress,
                                       Int32(ids.count),
                                       rowBuffer.baseAddress,
                                       rowCount32,
                                       errBuffer.baseAddress,
                                       256)
                    }
                }
            }
            guard status >= 0 else { return pending }
            for (i, row) in rows.enumerated() {
                guard row.found != 0, i < ids.count,
                      let index = indexByID[ids[i]] else { continue }
                let directory = Self.fieldString(row.dir)
                let title = Self.fieldString(row.title)
                let original = pending[index]
                pending[index] = RunningSession(
                    kind: original.kind, pid: original.pid,
                    cwd: original.cwd, tty: original.tty,
                    sessionID: original.sessionID,
                    directory: directory.isEmpty ? original.directory : directory,
                    title: title.isEmpty ? original.title : title)
            }
            return Self.dedupe(pending)
        }

        return Self.dedupe(pending)
    }

    private static func fieldString(_ tuple: Any) -> String {
        var bytes: [UInt8] = []
        for child in Mirror(reflecting: tuple).children {
            guard let byte = child.value as? Int8 else { continue }
            if byte == 0 { break }
            bytes.append(UInt8(bitPattern: byte))
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func dedupe(_ sessions: [RunningSession]) -> [RunningSession] {
        var seen: [String: RunningSession] = [:]
        for session in sessions {
            let key = "\(session.kind.rawValue)|\(session.tty)"
            if let existing = seen[key] {
                if session.title != nil && existing.title == nil {
                    seen[key] = session
                }
            } else {
                seen[key] = session
            }
        }
        return seen.values.sorted { a, b in
            if a.kind != b.kind { return a.kind == .claude }
            if a.tty != b.tty { return a.tty < b.tty }
            return a.pid < b.pid
        }
    }

    static func sessionID(in argv: String) -> String? {
        for arg in ["-s", "--session", "--resume"] {
            let marker = arg + " "
            if let range = argv.range(of: marker) {
                let rest = argv[range.upperBound...]
                let token = rest.split(separator: " ").first.map(String.init) ?? ""
                if token.hasPrefix("ses_") {
                    return token
                }
            }
        }
        return nil
    }
}
