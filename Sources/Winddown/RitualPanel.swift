import AppKit
import SwiftUI

/// Hosts the ritual view in a floating panel that appears above everything
/// when the cutoff hits. Deliberately not a lock screen: it can be escaped
/// via "Work late", but it demands an explicit choice.
@MainActor
final class RitualPanelController {
    static let shared = RitualPanelController()

    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.title = "Winddown"
            panel.titlebarAppearsTransparent = true
            panel.level = .floating
            panel.isFloatingPanel = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.contentView = NSHostingView(rootView: RitualView())
            self.panel = panel
        }
        // Closable only before the cutoff: at the cutoff itself the way out is
        // "End the day" or a logged "Work late", not a quiet dismiss.
        panel?.standardWindowButton(.closeButton)?.isHidden =
            AppState.shared.phase == .evening
        panel?.center()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

struct RitualView: View {
    @State private var finished = ""
    @State private var tomorrow = ""
    @State private var sessions: [ClaudeSession] = []
    @State private var isShowingOverride = false
    @State private var overrideReason = ""
    @ObservedObject private var state = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("That's it for today")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Capture where you left off, then close the laptop lid on work — not on life.")
                    .foregroundStyle(.secondary)
            }

            if !sessions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Claude Code today").font(.headline)
                    ForEach(sessions.prefix(5)) { session in
                        HStack(alignment: .top, spacing: 6) {
                            Text(shortProject(session.project))
                                .font(.system(.caption, design: .monospaced))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            Text(session.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("What I finished").font(.headline)
                TextEditor(text: $finished)
                    .font(.body)
                    .frame(minHeight: 70)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("First thing tomorrow").font(.headline)
                TextEditor(text: $tomorrow)
                    .font(.body)
                    .frame(minHeight: 70)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                // Only offered when the panel was opened by hand before the
                // cutoff. At the real cutoff the choice is end the day or
                // work late, not dismiss.
                if state.phase != .evening {
                    Button("Cancel") { RitualPanelController.shared.hide() }
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                }
                Button("Work late…") { isShowingOverride = true }
                    .controlSize(.large)
                Spacer()
                Button("End the day") {
                    AppState.shared.completeRitual(
                        finished: finished, tomorrow: tomorrow, sessions: sessions
                    )
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear { sessions = ClaudeSessions.today() }
        .sheet(isPresented: $isShowingOverride) {
            OverrideSheet(reason: $overrideReason, isPresented: $isShowingOverride)
        }
    }

    private func shortProject(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

/// Work-late flow: a reason is required so every extension leaves a trace in
/// the daily note.
struct OverrideSheet: View {
    @Binding var reason: String
    @Binding var isPresented: Bool
    @State private var minutes = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Working late").font(.title2.bold())
            Text("Why? This gets written into today's note.")
                .foregroundStyle(.secondary)
            TextField("e.g. prod incident on payouts", text: $reason)
                .textFieldStyle(.roundedBorder)
            Picker("For", selection: $minutes) {
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Keep working") {
                    AppState.shared.startOverride(reason: reason, minutes: minutes)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(reason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
