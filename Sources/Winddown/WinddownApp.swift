import SwiftUI

@main
struct WinddownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject var state = AppState.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(state: state, settings: settings)
        } label: {
            Image(systemName: iconName)
            if !state.menuTitle.isEmpty {
                Text(state.menuTitle)
            }
        }

        Settings {
            SettingsView()
        }
    }

    private var iconName: String {
        switch state.phase {
        case .working: "sunset"
        case .ramp: "sunset.fill"
        case .warning: "exclamationmark.circle.fill"
        case .workingLate: "moon.circle"
        case .evening: "moon.stars.fill"
        case .offDuty: "zzz"
        }
    }
}

struct MenuContent: View {
    @ObservedObject var state: AppState
    @ObservedObject var settings: AppSettings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Text(phaseLabel)

        Divider()

        switch state.phase {
        case .evening:
            Button("Work late…") { RitualPanelController.shared.show() }
        case .workingLate:
            Button("Done — back to evening") { state.endOverride() }
        case .working, .ramp, .warning:
            Button("End the day now") { RitualPanelController.shared.show() }
        case .offDuty:
            if settings.pausedUntil != nil {
                Button("Resume Winddown") { state.resume() }
            }
        }

        if state.phase != .offDuty {
            Button("Pause until tomorrow") { state.pauseUntilTomorrow() }
        }

        Button("Open today's note") {
            NSWorkspace.shared.open(URL(fileURLWithPath: DailyNote.path()))
        }

        Divider()

        Button("Settings…") {
            openSettings()
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")

        Button("Quit Winddown") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var phaseLabel: String {
        switch state.phase {
        case .working: "Working — cutoff at \(cutoffLabel)"
        case .ramp: "Winding down — cutoff at \(cutoffLabel)"
        case .warning: "Wrap up — almost \(cutoffLabel)"
        case .workingLate: "Working late (logged)"
        case .evening: "Evening — work apps are off"
        case .offDuty: settings.pausedUntil != nil ? "Paused until tomorrow" : "Off duty"
        }
    }

    private var cutoffLabel: String {
        String(format: "%d:%02d", settings.cutoffMinutes / 60, settings.cutoffMinutes % 60)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in AppState.shared.start() }
    }
}
