import AppKit

/// Hides work apps from the Dock during the evening and puts them back in
/// their original slots in the morning.
///
/// The Dock keeps its tiles in the `persistent-apps` array of
/// com.apple.dock; order in that array is left-to-right order in the Dock.
/// Hiding records each removed tile with its index, so restoring can insert
/// it back at the same position rather than appending to the end.
@MainActor
enum DockTiles {
    private static let dockDomain = "com.apple.dock"
    private static let tilesKey = "persistent-apps"
    /// Where the removed tiles are parked, as [{index, tile}] archived plist
    /// data, in Winddown's own defaults rather than the Dock's.
    private static let stashKey = "dockStash"

    static func hide(bundleIds: [String]) {
        guard !bundleIds.isEmpty, loadStash() == nil, !isSettling else { return }

        guard var tiles = currentTiles() else { return }

        var stash: [[String: Any]] = []
        // Back to front so recorded indices stay valid as entries are removed.
        for index in tiles.indices.reversed() {
            guard let path = appPath(of: tiles[index]),
                  let id = bundleId(atPath: path),
                  bundleIds.contains(id)
            else { continue }

            stash.append(["index": index, "tile": tiles[index]])
            tiles.remove(at: index)
        }
        guard !stash.isEmpty else { return }

        saveStash(stash)
        write(tiles: tiles)
    }

    static func restore() {
        guard !isSettling, let stash = loadStash(), var tiles = currentTiles() else { return }

        // Clear the stash first: a restore that partially fails must not leave
        // a stash behind for the next tick to apply again.
        clearStash()

        // Ascending index order, so each insert lands at its original slot.
        for entry in stash.sorted(by: { ($0["index"] as? Int ?? 0) < ($1["index"] as? Int ?? 0) }) {
            guard let tile = entry["tile"] as? [String: Any],
                  let path = appPath(of: tile)
            else { continue }

            // The Dock may have written its pre-restart list back to defaults,
            // so a tile can already be present. Inserting blind duplicates it.
            let isPresent = tiles.contains { appPath(of: $0) == path }
            guard !isPresent else { continue }

            let index = min(entry["index"] as? Int ?? tiles.count, tiles.count)
            tiles.insert(tile, at: index)
        }
        write(tiles: deduplicated(tiles))
    }

    /// Collapses repeated app paths, keeping the first occurrence. A safety net
    /// for a Dock list that already picked up duplicates.
    private static func deduplicated(_ tiles: [[String: Any]]) -> [[String: Any]] {
        var seenPaths: Set<String> = []
        return tiles.filter { tile in
            guard let path = appPath(of: tile) else { return true }

            return seenPaths.insert(path).inserted
        }
    }

    static var isHiding: Bool { loadStash() != nil }

    // MARK: - Dock plumbing

    private static func currentTiles() -> [[String: Any]]? {
        UserDefaults(suiteName: dockDomain)?.array(forKey: tilesKey) as? [[String: Any]]
    }

    /// A restarting Dock rewrites persistent-apps from its own memory, so a
    /// second write landing in that window can be lost or duplicated. Writes
    /// are refused until the restart settles.
    private static var lastWrite: Date?
    private static let restartSettleSeconds: TimeInterval = 5

    static var isSettling: Bool {
        guard let lastWrite else { return false }

        return Date().timeIntervalSince(lastWrite) < restartSettleSeconds
    }

    /// Restarting the Dock is the only way to make it reread its defaults.
    private static func write(tiles: [[String: Any]]) {
        guard let defaults = UserDefaults(suiteName: dockDomain) else { return }

        lastWrite = Date()
        defaults.set(tiles, forKey: tilesKey)
        defaults.synchronize()
        let restart = Process()
        restart.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        restart.arguments = ["Dock"]
        try? restart.run()
    }

    /// Digs the app path out of a tile's nested file-data dictionary.
    private static func appPath(of tile: [String: Any]) -> String? {
        guard let data = tile["tile-data"] as? [String: Any],
              let fileData = data["file-data"] as? [String: Any],
              let urlString = fileData["_CFURLString"] as? String
        else { return nil }

        return URL(string: urlString)?.path
    }

    private static func bundleId(atPath path: String) -> String? {
        Bundle(url: URL(fileURLWithPath: path))?.bundleIdentifier
    }

    // MARK: - Stash

    private static func saveStash(_ stash: [[String: Any]]) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: stash, requiringSecureCoding: false
        ) else { return }

        UserDefaults.standard.set(data, forKey: stashKey)
    }

    private static func loadStash() -> [[String: Any]]? {
        guard let data = UserDefaults.standard.data(forKey: stashKey),
              let stash = try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
                as? [[String: Any]],
              !stash.isEmpty
        else { return nil }

        return stash
    }

    private static func clearStash() {
        UserDefaults.standard.removeObject(forKey: stashKey)
    }
}
