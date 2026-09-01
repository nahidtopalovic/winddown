import AppKit
import SwiftUI

/// In-app replacement for system notifications: a small floating panel at the
/// top of the screen that auto-dismisses. Used because the app is ad-hoc
/// signed, so UNUserNotificationCenter refuses to register it.
@MainActor
enum Banner {
    private static var panel: NSPanel?
    private static var dismissTask: Task<Void, Never>?

    static func show(title: String, body: String, seconds: TimeInterval = 8) {
        dismissTask?.cancel()
        panel?.orderOut(nil)

        let content = BannerView(title: title, body: body, onDismiss: { dismiss() })
        let hosting = NSHostingView(rootView: content)
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
        panel.ignoresMouseEvents = false // click anywhere on it to dismiss
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - hosting.fittingSize.width / 2,
                y: frame.maxY - hosting.fittingSize.height - 12
            ))
        }
        panel.orderFrontRegardless()
        Self.panel = panel

        dismissTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }

            panel.orderOut(nil)
        }
    }

    static func dismiss() {
        dismissTask?.cancel()
        panel?.orderOut(nil)
    }
}

private struct BannerView: View {
    let title: String
    let body_: String
    let onDismiss: () -> Void

    init(title: String, body: String, onDismiss: @escaping () -> Void) {
        self.title = title
        self.body_ = body
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sunset.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(body_).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
        .frame(maxWidth: 420)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onDismiss() }
    }
}
