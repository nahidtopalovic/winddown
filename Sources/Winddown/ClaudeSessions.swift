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
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDirectory), isDirectory.boolValue,
                  let files = try? fm.contentsOfDirectory(atPath: dirPath)
            else { continue }

            for file in files where file.hasSuffix(".jsonl") {
                let path = "\(dirPath)/\(file)"
                guard
                    let attrs = try? fm.attributesOfItem(atPath: path),
                    let modified = attrs[.modificationDate] as? Date,
                    modified >= startOfDay,
                    let title = title(of: path)
                else { continue }

                sessions.append(ClaudeSession(
                    id: path,
                    project: decodeProjectPath(dir),
                    summary: title,
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

    /// Claude Code writes a `custom-title` line naming the session, rewriting
    /// it as the conversation moves on, so the last one describes what the
    /// session became. Sessions without one are skipped: the alternative was
    /// the opening prompt, which for a long-running session describes what it
    /// started as days ago, not what happened today.
    private static func title(of path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }

        defer { try? handle.close() }
        guard let data = try? handle.readToEnd(),
              let contents = String(data: data, encoding: .utf8)
        else { return nil }

        var latest: String?
        for line in contents.split(separator: "\n") {
            guard line.contains("\"custom-title\""),
                  let json = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                    as? [String: Any],
                  json["type"] as? String == "custom-title",
                  let title = json["customTitle"] as? String,
                  !title.isEmpty
            else { continue }

            latest = title
        }
        return latest.map(truncate)
    }

    private static func truncate(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > 120 ? String(flat.prefix(120)) + "…" : flat
    }
}
