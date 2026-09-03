import Foundation

/// All user-tunable configuration, backed by UserDefaults so the Settings
/// window and the schedule logic read the same values.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    /// Minutes after midnight. Default 18:00.
    @Published var cutoffMinutes: Int {
        didSet { defaults.set(cutoffMinutes, forKey: "cutoffMinutes") }
    }
    /// How long before cutoff the ramp (amber) starts.
    @Published var rampLeadMinutes: Int {
        didSet { defaults.set(rampLeadMinutes, forKey: "rampLeadMinutes") }
    }
    /// How long before cutoff the warning notification fires (red).
    @Published var warnLeadMinutes: Int {
        didSet { defaults.set(warnLeadMinutes, forKey: "warnLeadMinutes") }
    }
    /// Minutes after midnight when the blocked window ends the next morning. Default 05:00.
    @Published var blockEndMinutes: Int {
        didSet { defaults.set(blockEndMinutes, forKey: "blockEndMinutes") }
    }
    @Published var weekdaysOnly: Bool {
        didSet { defaults.set(weekdaysOnly, forKey: "weekdaysOnly") }
    }
    @Published var blockedBundleIds: [String] {
        didSet { defaults.set(blockedBundleIds, forKey: "blockedBundleIds") }
    }
    @Published var noteDirectory: String {
        didSet { defaults.set(noteDirectory, forKey: "noteDirectory") }
    }
    /// Seconds between the cutoff and apps actually closing, so the cutoff
    /// never takes an editor away without warning. 0 closes immediately.
    @Published var graceSeconds: Int {
        didSet { defaults.set(graceSeconds, forKey: "graceSeconds") }
    }
    /// Whether blocked apps are also pulled out of the Dock in the evening
    /// and put back in their original slots in the morning.
    @Published var hideDockTiles: Bool {
        didSet { defaults.set(hideDockTiles, forKey: "hideDockTiles") }
    }
    /// Wallpaper image paths; empty string disables wallpaper switching.
    @Published var workWallpaper: String {
        didSet { defaults.set(workWallpaper, forKey: "workWallpaper") }
    }
    @Published var eveningWallpaper: String {
        didSet { defaults.set(eveningWallpaper, forKey: "eveningWallpaper") }
    }

    // Runtime escape hatches. Persisted so they survive an app restart.
    /// Work-late extension: blocking is suspended until this date.
    @Published var overrideUntil: Date? {
        didSet { defaults.set(overrideUntil, forKey: "overrideUntil") }
    }
    /// Full pause: Winddown does nothing until this date (start of next day).
    @Published var pausedUntil: Date? {
        didSet { defaults.set(pausedUntil, forKey: "pausedUntil") }
    }
    /// Set when the ritual was completed, so it doesn't re-open the same evening.
    @Published var ritualDoneDay: String? {
        didSet { defaults.set(ritualDoneDay, forKey: "ritualDoneDay") }
    }
    /// Day key for which the evening was started before the cutoff, via
    /// "End the day now". Makes an early finish stick instead of being
    /// overruled by the clock.
    @Published var endedEarlyDay: String? {
        didSet { defaults.set(endedEarlyDay, forKey: "endedEarlyDay") }
    }

    private init() {
        cutoffMinutes = defaults.object(forKey: "cutoffMinutes") as? Int ?? 18 * 60
        rampLeadMinutes = defaults.object(forKey: "rampLeadMinutes") as? Int ?? 30
        warnLeadMinutes = defaults.object(forKey: "warnLeadMinutes") as? Int ?? 15
        blockEndMinutes = defaults.object(forKey: "blockEndMinutes") as? Int ?? 5 * 60
        weekdaysOnly = defaults.object(forKey: "weekdaysOnly") as? Bool ?? true
        blockedBundleIds = defaults.object(forKey: "blockedBundleIds") as? [String]
            ?? ["com.microsoft.VSCode", "com.anthropic.claudefordesktop"]
        noteDirectory = defaults.string(forKey: "noteDirectory")
            ?? NSString(string: "~/Documents/winddown").expandingTildeInPath
        graceSeconds = defaults.object(forKey: "graceSeconds") as? Int ?? 60
        hideDockTiles = defaults.object(forKey: "hideDockTiles") as? Bool ?? false
        workWallpaper = defaults.string(forKey: "workWallpaper") ?? ""
        eveningWallpaper = defaults.string(forKey: "eveningWallpaper") ?? ""
        overrideUntil = defaults.object(forKey: "overrideUntil") as? Date
        pausedUntil = defaults.object(forKey: "pausedUntil") as? Date
        ritualDoneDay = defaults.string(forKey: "ritualDoneDay")
        endedEarlyDay = defaults.string(forKey: "endedEarlyDay")
    }
}
