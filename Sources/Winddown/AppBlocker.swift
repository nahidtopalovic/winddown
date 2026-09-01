import AppKit
import UserNotifications

/// Quits blocked apps when evening mode starts and keeps them closed by
/// watching launch notifications. Termination is polite first (regular quit,
/// so unsaved state gets its save dialog), forced only if the app is still
/// running after a grace period.
@MainActor
final class AppBlocker {
    private var isActive = false
    private var bundleIds: Set<String> = []
    private var observer: NSObjectProtocol?

    func setActive(_ active: Bool, bundleIds ids: [String]) {
        bundleIds = Set(ids)
        guard active != isActive else { return }

        isActive = active
        if active {
            terminateRunningBlockedApps()
            observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] note in
                guard
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                else { return }

                Task { @MainActor in self?.handleLaunch(of: app) }
            }
        } else if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            self.observer = nil
        }
    }

    private func terminateRunningBlockedApps() {
        for app in NSWorkspace.shared.runningApplications {
            if let id = app.bundleIdentifier, bundleIds.contains(id) {
                terminate(app)
            }
        }
    }

    private func handleLaunch(of app: NSRunningApplication) {
        guard isActive, let id = app.bundleIdentifier, bundleIds.contains(id) else { return }

        terminate(app)
        notifyBlocked(appName: app.localizedName ?? id)
    }

    private func terminate(_ app: NSRunningApplication) {
        app.terminate()
        // Escalate only if it ignored the polite quit (e.g. stuck dialog).
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if !app.isTerminated { app.forceTerminate() }
        }
    }

    private func notifyBlocked(appName: String) {
        let content = UNMutableNotificationContent()
        content.title = "\(appName) is off for today"
        content.body = "Work day is over. Use \"Work late\" in Winddown if it's urgent."
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
