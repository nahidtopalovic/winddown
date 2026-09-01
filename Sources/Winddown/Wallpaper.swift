import AppKit

/// Switches the desktop wallpaper with the phase: work image during work
/// hours (including a work-late override), after-work image from the evening
/// on. Opt-in — does nothing while a path is unset.
@MainActor
enum Wallpaper {
    static func apply(for phase: Phase) {
        let settings = AppSettings.shared
        let isWorkTime = switch phase {
        case .working, .ramp, .warning, .workingLate: true
        case .evening, .offDuty: false
        }
        let path = isWorkTime ? settings.workWallpaper : settings.eveningWallpaper
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return }

        let url = URL(fileURLWithPath: path)
        for screen in NSScreen.screens {
            // Only touches the active space per screen; other spaces keep
            // their wallpaper until visited after the next transition.
            if NSWorkspace.shared.desktopImageURL(for: screen) != url {
                try? NSWorkspace.shared.setDesktopImageURL(url, for: screen)
            }
        }
    }
}
