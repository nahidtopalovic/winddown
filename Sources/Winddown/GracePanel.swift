import AppKit
import SwiftUI

/// The last chance before apps close. Shows a live countdown with extend
/// buttons, so the cutoff never takes an editor away mid-thought: the apps
/// keep running until this elapses.
@MainActor
final class GracePanelController {
    static let shared = GracePanelController()

    private var panel: NSPanel?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(secondsRemaining: @escaping () -> Int) {
        if panel == nil {
            let view = GraceView(secondsRemaining: secondsRemaining)
            let hosting = NSHostingView(rootView: view)
            hosting.frame.size = hosting.fittingSize

            let panel = NSPanel(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.contentView = hosting
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.level = .statusBar
            panel.hasShadow = true
            panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .transient]
            self.panel = panel
        }
        if let panel, let screen = NSScreen.main {
            let size = panel.contentView?.fittingSize ?? panel.frame.size
            panel.setContentSize(size)
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.maxY - size.height - 12
            ))
        }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct GraceView: View {
    let secondsRemaining: () -> Int
    @State private var seconds = 0
    /// Drives the countdown text; the panel outlives any single render.
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "moon.stars.fill")
                .font(.title2)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Closing work apps in \(seconds)s")
                    .font(.headline)
                Text("Save what you need, or take more time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 28)

            HStack(spacing: 6) {
                Button("+15m") { AppState.shared.extend(byMinutes: 15) }
                Button("+30m") { AppState.shared.extend(byMinutes: 30) }
                Button("+1h") { AppState.shared.extend(byMinutes: 60) }
            }
            .controlSize(.small)

            Button("Close now") { AppState.shared.endGraceNow() }
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .onAppear { seconds = secondsRemaining() }
        .onReceive(ticker) { _ in seconds = secondsRemaining() }
    }
}
