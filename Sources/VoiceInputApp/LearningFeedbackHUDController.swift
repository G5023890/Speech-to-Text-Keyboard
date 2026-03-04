import AppKit
import SwiftUI

private final class LearningFeedbackState: ObservableObject {
    @Published var text: String = ""
    @Published var isVisible: Bool = false
}

private struct LearningFeedbackHUDView: View {
    @ObservedObject var state: LearningFeedbackState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12, weight: .semibold))
            Text(state.text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(radius: 12)
        .opacity(state.isVisible ? 1 : 0)
        .scaleEffect(state.isVisible ? 1 : 0.96)
    }
}

final class LearningFeedbackHUDController {
    private let autoHideDelay: TimeInterval = 0.8
    private let minimumVisibility: TimeInterval = 0.25

    private var panel: NSPanel?
    private let state = LearningFeedbackState()
    private var shownAt: Date?
    private var hideWorkItem: DispatchWorkItem?

    func show(_ text: String) {
        ensurePanel()
        guard let panel else { return }

        state.text = text
        shownAt = Date()
        hideWorkItem?.cancel()

        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = panel.contentView?.fittingSize ?? NSSize(width: 220, height: 44)
        panel.setContentSize(fitting)
        position(panel: panel)
        panel.orderFrontRegardless()

        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
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
            withAnimation(.easeOut(duration: 0.16)) {
                self.state.isVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
                self?.panel?.orderOut(nil)
            }
        }
    }

    private func ensurePanel() {
        if panel != nil { return }

        let hosting = NSHostingView(rootView: LearningFeedbackHUDView(state: state))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
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
        self.panel = panel
    }

    private func position(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - panel.frame.width / 2
        let y = frame.midY - panel.frame.height / 2
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
