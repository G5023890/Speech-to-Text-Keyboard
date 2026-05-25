import AppKit
import SwiftUI

private final class RecordingHUDState: ObservableObject {
    @Published var isVisible = false
}

private struct RecordingHUDView: View {
    static let hudWidth: CGFloat = (103 / 1.5) * 1.1 // Increased by 10% from current size.

    @ObservedObject var state: RecordingHUDState

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)

            Text("Слушаю")
                .font(.system(size: 11, weight: .medium))
        }
        .frame(width: Self.hudWidth)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .shadow(radius: 15)
        .opacity(state.isVisible ? 1 : 0)
        .scaleEffect(state.isVisible ? 1 : 0.97)
        .offset(y: state.isVisible ? 0 : -10)
    }
}

final class RecordingHUDController {
    private let autoHideDelay: TimeInterval = 0.8
    private let minimumVisibility: TimeInterval = 0.4

    private var panel: NSPanel?
    private let state = RecordingHUDState()
    private var shownAt: Date?
    private var hideWorkItem: DispatchWorkItem?

    func show() {
        ensurePanel()
        guard let panel else { return }

        shownAt = Date()
        hideWorkItem?.cancel()
        position(panel: panel)
        panel.orderFrontRegardless()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            state.isVisible = true
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.hide()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideDelay, execute: workItem)
    }

    func hide(immediately: Bool = false) {
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if immediately {
            state.isVisible = false
            panel?.orderOut(nil)
            return
        }

        let elapsed = shownAt.map { Date().timeIntervalSince($0) } ?? minimumVisibility
        let delay = max(0, minimumVisibility - elapsed)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                self.state.isVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.panel?.orderOut(nil)
            }
        }
    }

    private func ensurePanel() {
        if panel != nil { return }
        let hosting = NSHostingView(rootView: RecordingHUDView(state: state))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.contentView = hosting
        panel.contentView?.wantsLayer = true
        hosting.layoutSubtreeIfNeeded()
        let fitting = hosting.fittingSize
        panel.setContentSize(fitting)
        self.panel = panel
    }

    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.maxY - panel.frame.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
