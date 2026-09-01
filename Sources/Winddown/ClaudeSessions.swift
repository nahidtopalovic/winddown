import Foundation

struct ClaudeSession: Identifiable {
    let id: String
    /// Decoded project path, e.g. /Users/nahid/projects/filmhub.
    let project: String
    let summary: String
    let modified: Date
}

/// Reads today's Claude Code activity from ~/.claude/projects so the ritual
/// panel can show what was in flight. Read-only; never touches session files.
enum ClaudeSessions {
    static func today() -> [ClaudeSession] {
        let root = NSString(string: "~/.claude/projects").expandingTildeInPath
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(atPath: root) else { return [] }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        var sessions: [ClaudeSession] = []

        for dir in projectDirs {
            let dirPath = "\(root)/\(dir)"
            guard let files = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let path = "\(dirPath)/\(file)"
                guard
                    let attrs = try? fm.attributesOfItem(atPath: path),
                    let modified = attrs[.modificationDate] as? Date,
                    modified >= startOfDay
                else { continue }

                sessions.append(ClaudeSession(
                    id: path,
                    project: decodeProjectPath(dir),
                    summary: summary(of: path),
                    modified: modified
                ))
            }
        }
        return sessions.sorted { $0.modified > $1.modified }
    }

    /// Directory names encode the project path with '-' for '/'. Lossy for
    /// paths that contain dashes, but good enough for display.
    private static func decodeProjectPath(_ dir: String) -> String {
        dir.hasPrefix("-") ? dir.replacingOccurrences(of: "-", with: "/") : dir
    }

    /// Best-effort one-liner: the session's summary line if present, else the
    /// first user message. Reads only the head of the file.
    private static func summary(of path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path),
              let data = try? handle.read(upToCount: 64 * 1024),
              let head = String(data: data, encoding: .utf8)
        else { return "" }

        var firstUserText = ""
        for line in head.split(separator: "\n").prefix(50) {
            guard
                let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            else { continue }

            if let summary = json["summary"] as? String {
                return truncate(summary)
            }
            if firstUserText.isEmpty,
               json["type"] as? String == "user",
               let message = json["message"] as? [String: Any],
               let content = message["content"] as? String,
               !content.hasPrefix("<") { // skip system-reminder / command wrappers
                firstUserText = content
            }
        }
        return truncate(firstUserText)
    }

    private static func truncate(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 120 ? String(flat.prefix(120)) + "…" : flat
    }
}
