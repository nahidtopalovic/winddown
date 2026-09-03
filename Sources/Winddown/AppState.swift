import AppKit
import Combine

enum Phase: Equatable {
    /// Normal work hours, nothing to do.
    case working
    /// Ramp started (amber icon).
    case ramp
    /// Final stretch before cutoff (red icon), notification fired.
    case warning
    /// Past cutoff with a work-late override active.
    case workingLate
    /// Past cutoff: ritual pending or done, work apps blocked.
    case evening
    /// No cutoff today (weekend or paused).
    case offDuty
}

/// Drives the whole app: computes the current phase from the wall clock every
/// second, fires the transition side effects (notification, ritual panel,
/// app blocker), and survives sleep/wake by recomputing on every tick instead
/// of scheduling one-shot timers at absolute dates.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: Phase = .working
    /// Separate observable so the once-a-minute countdown re-renders only the
    /// menu bar label. If AppState published it, every change would rebuild
    /// the open menu and snap its submenus shut.
    @MainActor
    final class MenuTitle: ObservableObject {
        @Published var text: String = ""
    }
    let menuTitle = MenuTitle()

    let settings = AppSettings.shared
    private let blocker = AppBlocker()
    private var timer: Timer?
    private var didNotifyWarning = false
    private var settingsSink: AnyCancellable?

    private init() {}

    func start() {
        tick()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Re-evaluate immediately when settings change (e.g. cutoff moved for testing).
        settingsSink = settings.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        let now = Date()
        let newPhase = computePhase(at: now)

        if newPhase != phase {
            transition(to: newPhase, at: now)
        }
        let newTitle = title(for: newPhase, at: now)
        if newTitle != menuTitle.text { menuTitle.text = newTitle }
        // Keep the blocker in sync even without a phase change (override expiry,
        // blocklist edits).
        let shouldBlock = newPhase == .evening
        blocker.setActive(shouldBlock, bundleIds: settings.blockedBundleIds)
        // Every tick, not just transitions: self-heals after space switches,
        // settings edits, and manual wallpaper changes. No-op when unchanged.
        Wallpaper.apply(for: newPhase)
        syncDockTiles(shouldHide: shouldBlock && settings.hideDockTiles)
        // Ritual can become due while already in .evening (override expired).
        // Not after midnight though: an unfinished ritual is not worth
        // opening a window over if you're waking the laptop at 3am.
        if newPhase == .evening,
           !isRitualDone(at: now),
           minutes(of: now) >= settings.blockEndMinutes,
           !RitualPanelController.shared.isVisible {
            RitualPanelController.shared.show()
        }
    }

    /// Restores tiles whenever hiding should not be in effect, including
    /// after the setting is switched off mid-evening.
    private func syncDockTiles(shouldHide: Bool) {
        if shouldHide {
            DockTiles.hide(bundleIds: settings.blockedBundleIds)
        } else if DockTiles.isHiding {
            DockTiles.restore()
        }
    }

    private func transition(to newPhase: Phase, at now: Date) {
        phase = newPhase
        switch newPhase {
        case .warning:
            if !didNotifyWarning {
                didNotifyWarning = true
                Banner.show(
                    title: "\(settings.warnLeadMinutes) minutes left",
                    body: "Start wrapping up. Commit what's in flight."
                )
            }
        case .evening:
            break // ritual handled in tick(), blocker in tick()
        case .working, .ramp, .offDuty, .workingLate:
            didNotifyWarning = newPhase == .workingLate
        }
    }

    // MARK: - Phase math

    /// Minutes since midnight in the local calendar.
    private func minutes(of date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    private func isWorkday(_ date: Date) -> Bool {
        guard settings.weekdaysOnly else { return true }

        return !Calendar.current.isDateInWeekend(date)
    }

    /// The workday a moment belongs to, which is not the calendar day between
    /// midnight and the block end: 1am Wednesday is still Tuesday's evening.
    /// Every day-scoped flag (ritual done, ended early) must use this, or the
    /// pre-dawn hours look like a fresh day and re-arm last night's ritual.
    private func workdayKey(for date: Date) -> String {
        guard minutes(of: date) < settings.blockEndMinutes else {
            return DailyNote.dayKey(for: date)
        }

        let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        return DailyNote.dayKey(for: previousDay)
    }

    /// The cutoff actually in force, in minutes after midnight. An extension
    /// pushes it later, so the ramp, the warning and the countdown all follow
    /// the new end of day instead of the one in settings. Returns nil when the
    /// override runs past midnight, which means today has no cutoff left.
    /// Label for the end of day in force, "18:00" or an extended "19:30".
    var effectiveCutoffLabel: String {
        guard let cutoff = effectiveCutoffMinutes(at: Date()) else { return "tomorrow" }

        return String(format: "%d:%02d", cutoff / 60, cutoff % 60)
    }

    private func effectiveCutoffMinutes(at now: Date) -> Int? {
        guard let until = settings.overrideUntil, now < until else {
            return settings.cutoffMinutes
        }
        guard Calendar.current.isDate(until, inSameDayAs: now) else { return nil }

        return max(settings.cutoffMinutes, minutes(of: until))
    }

    func computePhase(at now: Date) -> Phase {
        if let paused = settings.pausedUntil, now < paused { return .offDuty }

        let mins = minutes(of: now)

        // Early morning belongs to the previous day's evening window.
        if mins < settings.blockEndMinutes {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
            if isWorkday(yesterday) && minutes(of: now) >= 0 && settings.cutoffMinutes < 24 * 60 {
                return overrideActive(at: now) ? .workingLate : .evening
            }
            return .offDuty
        }

        guard isWorkday(now) else { return .offDuty }

        // An early finish outranks the clock: once the day is called, it stays
        // called until tomorrow.
        if settings.endedEarlyDay == workdayKey(for: now) {
            return overrideActive(at: now) ? .workingLate : .evening
        }
        // An extension past midnight leaves no cutoff today.
        guard let cutoff = effectiveCutoffMinutes(at: now) else { return .workingLate }

        if mins >= cutoff {
            return overrideActive(at: now) ? .workingLate : .evening
        }
        if mins >= cutoff - settings.warnLeadMinutes { return .warning }
        if mins >= cutoff - settings.rampLeadMinutes { return .ramp }
        return .working
    }

    /// True while the evening was started by hand and the scheduled cutoff is
    /// still ahead — the only case where going back to work makes sense.
    var didEndEarly: Bool {
        let now = Date()
        return settings.endedEarlyDay == workdayKey(for: now)
            && minutes(of: now) >= settings.blockEndMinutes
            && minutes(of: now) < settings.cutoffMinutes
    }

    func overrideActive(at now: Date) -> Bool {
        guard let until = settings.overrideUntil else { return false }

        return now < until
    }

    private func isRitualDone(at now: Date) -> Bool {
        settings.ritualDoneDay == workdayKey(for: now)
    }

    private func title(for phase: Phase, at now: Date) -> String {
        switch phase {
        case .offDuty:
            return ""
        case .evening:
            return "off"
        case .workingLate:
            let left = Int(settings.overrideUntil!.timeIntervalSince(now)) / 60 + 1
            return "late \(left)m"
        case .working, .ramp, .warning:
            let mins = minutes(of: now)
            let left = max(0, (effectiveCutoffMinutes(at: now) ?? settings.cutoffMinutes) - mins)
            if left >= 120 { return "" } // only show countdown when the end is near
            let hours = left / 60, rem = left % 60
            return hours > 0 ? "\(hours)h \(rem)m" : "\(rem)m"
        }
    }

    // MARK: - Actions

    func startOverride(reason: String, minutes: Int) {
        let until = Date().addingTimeInterval(TimeInterval(minutes * 60))
        settings.overrideUntil = until
        DailyNote.append(section: "Override", body: "Worked late \(minutes) min: \(reason)")
        RitualPanelController.shared.hide()
        tick()
    }

    func endOverride() {
        settings.overrideUntil = nil
        tick()
    }

    /// Buys more work time before the cutoff hits, from the menu. Extending
    /// an active override adds to its remaining time; extending during work
    /// hours starts one from the scheduled cutoff, so "30 more minutes" at
    /// 17:00 still means 18:30 rather than 17:30.
    func extend(byMinutes added: Int) {
        let now = Date()
        let base: Date
        if let until = settings.overrideUntil, now < until {
            base = until
        } else {
            base = Calendar.current.date(
                bySettingHour: settings.cutoffMinutes / 60,
                minute: settings.cutoffMinutes % 60,
                second: 0, of: now
            ) ?? now
        }
        settings.overrideUntil = max(base, now).addingTimeInterval(TimeInterval(added * 60))
        // An extension overrules a finish called earlier today.
        settings.endedEarlyDay = nil
        DailyNote.append(section: "Extended", body: "Pushed the cutoff by \(added) min")
        didNotifyWarning = false // the new cutoff deserves its own warning
        tick()
    }

    /// Undo an early finish: back to work, and the ritual can run again.
    func resumeWorkday() {
        settings.endedEarlyDay = nil
        settings.ritualDoneDay = nil
        settings.overrideUntil = nil
        tick()
    }

    func pauseUntilTomorrow() {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: Date()))!
        let resume = cal.date(byAdding: .minute, value: settings.blockEndMinutes, to: tomorrow)!
        settings.pausedUntil = resume
        RitualPanelController.shared.hide()
        tick()
    }

    func resume() {
        settings.pausedUntil = nil
        tick()
    }

    func completeRitual(finished: String, tomorrow: String, sessions: [ClaudeSession]) {
        let today = workdayKey(for: Date())
        settings.ritualDoneDay = today
        settings.endedEarlyDay = today
        DailyNote.writeRitual(finished: finished, tomorrow: tomorrow, sessions: sessions)
        RitualPanelController.shared.hide()
        tick()
    }
}
