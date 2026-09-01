import Foundation

/// One markdown file per day in the configured note directory. The ritual
/// writes the main body; overrides append as they happen.
enum DailyNote {
    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func path(for date: Date = Date()) -> String {
        "\(AppSettings.shared.noteDirectory)/\(dayKey(for: date)).md"
    }

    static func writeRitual(finished: String, tomorrow: String, sessions: [ClaudeSession]) {
        var body = "## Done for today — \(timeNow())\n\n"
        if !finished.isEmpty {
            body += "### What I finished\n\(finished)\n\n"
        }
        if !tomorrow.isEmpty {
            body += "### First thing tomorrow\n\(tomorrow)\n\n"
        }
        if !sessions.isEmpty {
            body += "### Claude Code sessions today\n"
            for session in sessions {
                body += "- `\(session.project)` — \(session.summary)\n"
            }
            body += "\n"
        }
        append(raw: body)
    }

    static func append(section: String, body: String) {
        append(raw: "## \(section) — \(timeNow())\n\(body)\n\n")
    }

    private static func append(raw: String) {
        let fm = FileManager.default
        let dir = AppSettings.shared.noteDirectory
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let notePath = path()
        if !fm.fileExists(atPath: notePath) {
            let header = "# \(dayKey(for: Date()))\n\n"
            fm.createFile(atPath: notePath, contents: Data(header.utf8))
        }
        if let handle = FileHandle(forWritingAtPath: notePath) {
            handle.seekToEndOfFile()
            handle.write(Data(raw.utf8))
            try? handle.close()
        }
    }

    private static func timeNow() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}
