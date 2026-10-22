import Foundation

private let estimatorQueueLabel: String = {
    let identifier = Bundle.main.bundleIdentifier ?? "dev.arkab.macmon"
    return "\(identifier).jsonl"
}()

public final class LocalUsageEstimator {
    private struct State: Codable {
        var offsets: [String: UInt64] = [:]
    }

    private static let queue = DispatchQueue(label: estimatorQueueLabel,
                                             qos: .utility)
    private static let window: TimeInterval = 5 * 3600 + 900
    private static let firstRunTail: UInt64 = 8 * 1024 * 1024

    public static func estimateTokens(completion: @escaping (Int) -> Void) {
        queue.async {
            completion(compute())
        }
    }

    private static func compute() -> Int {
        let cutoff = Date().addingTimeInterval(-window)
        var state = loadState()
        var total = 0

        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: Paths.claudeProjects,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return 0
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate,
                  modified > cutoff,
                  let size = values.fileSize else {
                continue
            }

            let path = url.path
            let fileSize = UInt64(max(0, size))
            var offset = state.offsets[path] ?? firstRunOffset(for: fileSize)
            if offset > fileSize {
                offset = 0
            }
            guard fileSize > offset else {
                state.offsets[path] = fileSize
                continue
            }

            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            do {
                try handle.seek(toOffset: offset)
            } catch {
                continue
            }
            guard let data = try? handle.readToEnd() else { continue }

            var lineStart = 0
            var consumed = 0
            let bytes = [UInt8](data)
            var index = 0
            while index < bytes.count {
                if bytes[index] == 0x0A {
                    let line = Array(bytes[lineStart..<index])
                    total += tokens(in: line, cutoff: cutoff)
                    consumed = index + 1
                    lineStart = index + 1
                }
                index += 1
            }

            state.offsets[path] = offset + UInt64(consumed)
        }

        pruneState(&state)
        saveState(state)
        return total
    }

    private static func firstRunOffset(for size: UInt64) -> UInt64 {
        size > firstRunTail ? size - firstRunTail : 0
    }

    private static func tokens(in line: [UInt8], cutoff: Date) -> Int {
        guard !line.isEmpty else { return 0 }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
            return 0
        }
        if let timestamp = object["timestamp"] as? String,
           let date = ISO8601DateFormatter.macmon.date(from: timestamp),
           date < cutoff {
            return 0
        }
        guard let message = object["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any] else {
            return 0
        }

        var sum = 0
        for key in ["input_tokens", "output_tokens",
                    "cache_creation_input_tokens", "cache_read_input_tokens"] {
            if let value = usage[key] as? Int {
                sum += value
            } else if let value = usage[key] as? Double {
                sum += Int(value)
            }
        }
        return sum
    }

    private static func loadState() -> State {
        guard let data = try? Data(contentsOf: Paths.jsonlState),
              let state = try? JSONDecoder().decode(State.self, from: data) else {
            return State()
        }
        return state
    }

    private static func saveState(_ state: State) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Paths.jsonlState, options: .atomic)
    }

    private static func pruneState(_ state: inout State) {
        guard state.offsets.count > 200 else { return }
        let existing = Set(state.offsets.keys.compactMap { key -> String? in
            FileManager.default.fileExists(atPath: key) ? key : nil
        })
        state.offsets = state.offsets.filter { existing.contains($0.key) }
    }
}

extension ISO8601DateFormatter {
    static let macmon: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let macmonNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
