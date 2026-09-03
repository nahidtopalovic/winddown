import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var newBundleId = ""
    @State private var isLaunchAtLoginOn = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Schedule") {
                TimeMinutePicker(label: "End of workday", minutes: $settings.cutoffMinutes)
                Stepper(
                    "Ramp starts \(settings.rampLeadMinutes) min before",
                    value: $settings.rampLeadMinutes, in: 5...120, step: 5
                )
                Stepper(
                    "Warning \(settings.warnLeadMinutes) min before",
                    value: $settings.warnLeadMinutes, in: 5...60, step: 5
                )
                TimeMinutePicker(label: "Blocked until (next morning)", minutes: $settings.blockEndMinutes)
                Toggle("Weekdays only", isOn: $settings.weekdaysOnly)
            }

            Section("Blocked apps") {
                ForEach(settings.blockedBundleIds, id: \.self) { id in
                    HStack {
                        Text(id).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            settings.blockedBundleIds.removeAll { $0 == id }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Bundle id, e.g. com.figma.Desktop", text: $newBundleId)
                        .textFieldStyle(.roundedBorder)
                    Button("Add") {
                        let id = newBundleId.trimmingCharacters(in: .whitespaces)
                        guard !id.isEmpty, !settings.blockedBundleIds.contains(id) else { return }

                        settings.blockedBundleIds.append(id)
                        newBundleId = ""
                    }
                }
                Text("Find an app's bundle id with: osascript -e 'id of app \"AppName\"'")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Also hide them from the Dock", isOn: $settings.hideDockTiles)
                Text("Removed at the cutoff and put back in the same Dock positions in the morning. Restarts the Dock each time.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Wallpaper") {
                WallpaperPicker(label: "During work", path: $settings.workWallpaper)
                WallpaperPicker(label: "After work", path: $settings.eveningWallpaper)
                Text("Set both to have the desktop switch moods at the cutoff. Leave empty to disable.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Notes") {
                TextField("Note directory", text: $settings.noteDirectory)
                    .font(.system(.body, design: .monospaced))
            }

            Section {
                Toggle("Launch at login", isOn: $isLaunchAtLoginOn)
                    .onChange(of: isLaunchAtLoginOn) { _, isOn in
                        do {
                            if isOn { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            isLaunchAtLoginOn = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
    }
}

struct WallpaperPicker: View {
    let label: String
    @Binding var path: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(path.isEmpty ? "None" : URL(fileURLWithPath: path).lastPathComponent)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                // Start in Apple's built-in wallpapers (the same images the
                // System Settings picker offers, minus the aerials — those
                // have no public API).
                panel.directoryURL = URL(
                    fileURLWithPath: path.isEmpty
                        ? "/System/Library/Desktop Pictures"
                        : (path as NSString).deletingLastPathComponent
                )
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
            if !path.isEmpty {
                Button("Clear") { path = "" }
            }
        }
    }
}

/// Hour:minute picker over a minutes-after-midnight binding, which is how the
/// schedule stores times.
struct TimeMinutePicker: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(
            label,
            selection: Binding(
                get: {
                    Calendar.current.date(
                        bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()
                    ) ?? Date()
                },
                set: { date in
                    let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                    minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                }
            ),
            displayedComponents: .hourAndMinute
        )
    }
}
