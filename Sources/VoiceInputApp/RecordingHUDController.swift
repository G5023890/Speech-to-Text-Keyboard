import AppKit
import SwiftUI

private struct NotchHUDMetrics: Equatable {
    let panelFrame: NSRect
    let notchRect: CGRect
    let leftAuxiliaryRect: CGRect
    let rightAuxiliaryRect: CGRect
    let bandHeight: CGFloat

    static func forScreen(_ screen: NSScreen) -> NotchHUDMetrics {
        let frame = screen.frame
        let safeAreaTop = screen.safeAreaInsets.top
        let leftArea = screen.auxiliaryTopLeftArea ?? .zero
        let rightArea = screen.auxiliaryTopRightArea ?? .zero
        let auxiliaryHeight = max(leftArea.height, rightArea.height)
        let bandHeight = max(28, max(safeAreaTop, auxiliaryHeight))
        let panelFrame = NSRect(
            x: frame.minX,
            y: frame.maxY - bandHeight,
            width: frame.width,
            height: bandHeight
        )

        let inferredNotchWidth = max(160, frame.width - leftArea.width - rightArea.width)
        let notchRect: CGRect
        if !leftArea.isEmpty && !rightArea.isEmpty && rightArea.minX > leftArea.maxX {
            notchRect = CGRect(
                x: leftArea.maxX - frame.minX,
                y: 0,
                width: rightArea.minX - leftArea.maxX,
                height: bandHeight
            )
        } else {
            notchRect = CGRect(
                x: (frame.width - inferredNotchWidth) / 2,
                y: 0,
                width: inferredNotchWidth,
                height: bandHeight
            )
        }

        return NotchHUDMetrics(
            panelFrame: panelFrame,
            notchRect: notchRect,
            leftAuxiliaryRect: CGRect(
                x: leftArea.minX - frame.minX,
                y: 0,
                width: leftArea.width,
                height: bandHeight
            ),
            rightAuxiliaryRect: CGRect(
                x: rightArea.minX - frame.minX,
                y: 0,
                width: rightArea.width,
                height: bandHeight
            ),
            bandHeight: bandHeight
        )
    }
}

private struct FloatingParticle: Identifiable {
    enum Side {
        case screenLeft
        case screenRight
    }

    let id = UUID()
    let side: Side
    let startX: CGFloat
    let endX: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let controlX: CGFloat
    let controlY: CGFloat
    var progress: CGFloat = 0
    let duration: Double
    let color: Color
    let glowColor: Color
    let size: CGFloat
}

private struct NotchGlow: Equatable {
    let centerX: CGFloat
    let centerY: CGFloat
    let coreRadius: CGFloat
    let haloRadius: CGFloat
}

@MainActor
private final class NotchAnimationViewModel: ObservableObject {
    @Published var particles: [FloatingParticle] = []

    private var spawnTimer: Timer?
    private var updateTimer: Timer?
    private(set) var metrics: NotchHUDMetrics?

    func start(metrics: NotchHUDMetrics) {
        self.metrics = metrics
        particles.removeAll(keepingCapacity: true)
        stopTimers()
        spawnParticles()

        spawnTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.spawnParticles()
            }
        }

        updateTimer = Timer.scheduledTimer(withTimeInterval: 1 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.update()
            }
        }
    }

    func stop() {
        stopTimers()
        particles.removeAll()
    }

    private func stopTimers() {
        spawnTimer?.invalidate()
        updateTimer?.invalidate()
        spawnTimer = nil
        updateTimer = nil
    }

    private func spawnParticles() {
        guard let metrics else { return }
        particles.append(makeParticle(side: .screenLeft, metrics: metrics))
        particles.append(makeParticle(side: .screenLeft, metrics: metrics))
        particles.append(makeParticle(side: .screenRight, metrics: metrics))
        particles.append(makeParticle(side: .screenRight, metrics: metrics))
        if particles.count > 48 {
            particles.removeFirst(particles.count - 48)
        }
    }

    private func makeParticle(side: FloatingParticle.Side, metrics: NotchHUDMetrics) -> FloatingParticle {
        let bandHeight = metrics.bandHeight
        let verticalPadding = max(3, floor((bandHeight - 10) / 6))
        let minY = verticalPadding
        let maxY = max(minY + 1, bandHeight - verticalPadding - 1)
        let startY = CGFloat.random(in: minY...maxY)
        let duration = Double.random(in: 0.64...0.94)
        let notchMinX = metrics.notchRect.minX
        let notchMaxX = metrics.notchRect.maxX
        let sideTravel = max(42, min(88, min(metrics.leftAuxiliaryRect.width, metrics.rightAuxiliaryRect.width) * 0.2))
        let leftTravel = max(sideTravel + 56, min(168, metrics.leftAuxiliaryRect.width * 0.52))
        let leftStart = max(metrics.leftAuxiliaryRect.minX + 4, notchMinX - leftTravel)
        let leftEnd = notchMinX - 6
        let rightStart = notchMaxX + 6
        let rightEnd = min(metrics.rightAuxiliaryRect.maxX - 6, notchMaxX + sideTravel + 20)

        if side == .screenLeft {
            return FloatingParticle(
                side: .screenLeft,
                startX: leftStart,
                endX: leftEnd,
                startY: startY,
                endY: CGFloat.random(in: minY...maxY),
                controlX: notchMinX - CGFloat.random(in: 34...62),
                controlY: CGFloat.random(in: minY...maxY),
                duration: duration,
                color: Color(red: 0.78, green: 0.98, blue: 1.0),
                glowColor: Color(red: 0.50, green: 0.88, blue: 1.0),
                size: min(14, max(8, bandHeight - 14))
            )
        }

        return FloatingParticle(
            side: .screenRight,
            startX: rightStart,
            endX: rightEnd,
            startY: startY,
            endY: CGFloat.random(in: minY...maxY),
            controlX: notchMaxX + CGFloat.random(in: 24...42),
            controlY: CGFloat.random(in: minY...maxY),
            duration: duration,
            color: Color(red: 0.80, green: 1.0, blue: 0.90),
            glowColor: Color(red: 0.44, green: 1.0, blue: 0.82),
            size: min(11, max(7, bandHeight - 16))
        )
    }

    private func update() {
        let dt = CGFloat(1.0 / 60.0)

        for index in particles.indices {
            particles[index].progress += dt / CGFloat(particles[index].duration)
        }
        particles.removeAll { $0.progress >= 1.0 }
    }
}

private final class RecordingHUDState: ObservableObject {
    @Published var isVisible = false
    @Published var metrics = NotchHUDMetrics(
        panelFrame: .zero,
        notchRect: .zero,
        leftAuxiliaryRect: .zero,
        rightAuxiliaryRect: .zero,
        bandHeight: 28
    )
}

private struct ParticleView: View {
    let particle: FloatingParticle

    var body: some View {
        let t = particle.progress
        let mt = 1 - t
        let x = mt * mt * particle.startX
            + 2 * mt * t * particle.controlX
            + t * t * particle.endX
        let y = mt * mt * particle.startY
            + 2 * mt * t * particle.controlY
            + t * t * particle.endY
        let alpha = particleOpacity(for: t)

        RoundedRectangle(cornerRadius: particle.size / 2, style: .continuous)
            .fill(particle.color.opacity(alpha))
            .frame(width: particle.size * 1.7, height: particle.size * 0.72)
            .shadow(color: .black.opacity(alpha * 0.55), radius: 1.5, x: 0, y: 1)
            .shadow(color: particle.glowColor.opacity(alpha), radius: 10)
            .shadow(color: particle.glowColor.opacity(alpha * 0.9), radius: 20)
            .shadow(color: particle.color.opacity(alpha * 0.5), radius: 30)
            .position(x: x, y: y)
    }

    private func particleOpacity(for progress: CGFloat) -> Double {
        if progress < 0.14 {
            return Double(progress / 0.14)
        }
        if progress > 0.82 {
            return Double((1 - progress) / 0.18)
        }
        return 1
    }
}

private struct NotchView: View {
    let metrics: NotchHUDMetrics
    let isVisible: Bool

    var body: some View {
        let capsuleWidth = max(14, min(44, metrics.notchRect.width * 0.16))
        let capsuleHeight = max(3, min(8, metrics.bandHeight * 0.24))
        let sideBarHeight = max(5, min(10, metrics.bandHeight * 0.32))

        ZStack {
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.28, green: 0.78, blue: 1.0).opacity(0.18),
                            Color(red: 0.38, green: 1.0, blue: 0.82).opacity(0.24),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: capsuleWidth + 26, height: capsuleHeight + 8)
                .blur(radius: 7)

            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 2.4, height: sideBarHeight + 1)
                    .shadow(color: Color.white.opacity(0.18), radius: 2)
                RoundedRectangle(cornerRadius: capsuleHeight / 2, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: capsuleWidth, height: capsuleHeight)
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
                    .shadow(color: Color.white.opacity(0.08), radius: 5)
                    .overlay(
                        Circle()
                            .fill(Color(red: 0.54, green: 1.0, blue: 0.80).opacity(0.98))
                            .frame(width: 4.2, height: 4.2)
                            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
                            .shadow(color: Color(red: 0.54, green: 1.0, blue: 0.80).opacity(0.95), radius: 6)
                            .shadow(color: Color(red: 0.54, green: 1.0, blue: 0.80).opacity(0.6), radius: 12)
                            .scaleEffect(isVisible ? 1 : 0.55)
                            .animation(.easeInOut(duration: 0.82).repeatForever(autoreverses: true), value: isVisible)
                    )
                Capsule()
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 2.4, height: sideBarHeight + 1)
                    .shadow(color: Color.white.opacity(0.18), radius: 2)
            }
        }
        .position(x: metrics.notchRect.midX, y: metrics.bandHeight - capsuleHeight)
    }
}

private struct NotchGlowView: View {
    let glow: NotchGlow

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.62, green: 0.90, blue: 1.0).opacity(0.34),
                            Color(red: 0.38, green: 0.68, blue: 1.0).opacity(0.20),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: glow.haloRadius
                    )
                )
                .frame(width: glow.haloRadius * 2, height: glow.haloRadius * 2)
                .blur(radius: 8)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color(red: 0.84, green: 0.96, blue: 1.0).opacity(0.44),
                            Color(red: 0.56, green: 0.84, blue: 1.0).opacity(0.24),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: glow.coreRadius
                    )
                )
                .frame(width: glow.coreRadius * 2, height: glow.coreRadius * 2)
                .shadow(color: Color.white.opacity(0.18), radius: 6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.34),
                            Color(red: 0.78, green: 0.94, blue: 1.0).opacity(0.36),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: glow.coreRadius * 0.62
                    )
                )
                .frame(width: glow.coreRadius * 1.26, height: glow.coreRadius * 1.26)
                .blur(radius: 2.5)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color(red: 0.84, green: 0.98, blue: 1.0).opacity(0.28),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: glow.coreRadius * 0.32
                    )
                )
                .frame(width: glow.coreRadius * 0.72, height: glow.coreRadius * 0.72)
                .blur(radius: 1.4)
        }
        .position(x: glow.centerX, y: glow.centerY)
    }
}

private struct BeamLines: View {
    let metrics: NotchHUDMetrics

    var body: some View {
        let horizontalSpan = max(72, min(150, min(metrics.leftAuxiliaryRect.width, metrics.rightAuxiliaryRect.width) * 0.3))
        let leftSpan = max(horizontalSpan + 52, min(188, metrics.leftAuxiliaryRect.width * 0.54))
        let leftStart = max(metrics.leftAuxiliaryRect.minX, metrics.notchRect.minX - leftSpan)
        let leftEnd = metrics.notchRect.minX
        let rightStart = metrics.notchRect.maxX
        let rightEnd = min(metrics.rightAuxiliaryRect.maxX, metrics.notchRect.maxX + horizontalSpan)

        Canvas { context, _ in
            let midY = metrics.bandHeight / 2

            if leftEnd > leftStart {
                var leftAura = Path()
                leftAura.move(to: CGPoint(x: leftStart + 6, y: midY))
                leftAura.addLine(to: CGPoint(x: leftEnd - 1, y: midY))
                context.stroke(
                    leftAura,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.52, green: 0.90, blue: 1.0).opacity(0.10),
                            Color(red: 0.52, green: 0.90, blue: 1.0).opacity(0.34),
                            Color.white.opacity(0.28)
                        ]),
                        startPoint: CGPoint(x: leftStart + 6, y: midY),
                        endPoint: CGPoint(x: leftEnd - 1, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: 7.4, lineCap: .round)
                )

                var leftPath = Path()
                leftPath.move(to: CGPoint(x: leftStart + 8, y: midY))
                leftPath.addLine(to: CGPoint(x: leftEnd - 2, y: midY))
                context.stroke(
                    leftPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color(red: 0.46, green: 0.86, blue: 1.0).opacity(0.14),
                            Color(red: 0.72, green: 0.96, blue: 1.0).opacity(0.98),
                            Color.white.opacity(0.64)
                        ]),
                        startPoint: CGPoint(x: leftStart + 8, y: midY),
                        endPoint: CGPoint(x: leftEnd - 2, y: midY)
                    ),
                    lineWidth: 2.4
                )
            }

            if rightEnd > rightStart {
                var rightAura = Path()
                rightAura.move(to: CGPoint(x: rightStart + 1, y: midY))
                rightAura.addLine(to: CGPoint(x: rightEnd - 6, y: midY))
                context.stroke(
                    rightAura,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.26),
                            Color(red: 0.56, green: 1.0, blue: 0.80).opacity(0.34),
                            Color(red: 0.56, green: 1.0, blue: 0.80).opacity(0.10)
                        ]),
                        startPoint: CGPoint(x: rightStart + 1, y: midY),
                        endPoint: CGPoint(x: rightEnd - 6, y: midY)
                    ),
                    style: StrokeStyle(lineWidth: 7.4, lineCap: .round)
                )

                var rightPath = Path()
                rightPath.move(to: CGPoint(x: rightStart + 2, y: midY))
                rightPath.addLine(to: CGPoint(x: rightEnd - 8, y: midY))
                context.stroke(
                    rightPath,
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.white.opacity(0.52),
                            Color(red: 0.76, green: 1.0, blue: 0.86).opacity(0.98),
                            Color(red: 0.62, green: 1.0, blue: 0.76).opacity(0.10)
                        ]),
                        startPoint: CGPoint(x: rightStart + 2, y: midY),
                        endPoint: CGPoint(x: rightEnd - 8, y: midY)
                    ),
                    lineWidth: 2.4
                )
            }

            if leftEnd > leftStart {
                var leftGlow = Path()
                leftGlow.move(to: CGPoint(x: leftEnd - 18, y: midY))
                leftGlow.addLine(to: CGPoint(x: leftEnd - 1, y: midY))
                context.stroke(
                    leftGlow,
                    with: .color(Color(red: 0.72, green: 0.96, blue: 1.0).opacity(0.92)),
                    style: StrokeStyle(lineWidth: 5.8, lineCap: .round)
                )
            }

            if rightEnd > rightStart {
                var rightGlow = Path()
                rightGlow.move(to: CGPoint(x: rightStart + 1, y: midY))
                rightGlow.addLine(to: CGPoint(x: rightStart + 18, y: midY))
                context.stroke(
                    rightGlow,
                    with: .color(Color(red: 0.78, green: 1.0, blue: 0.88).opacity(0.92)),
                    style: StrokeStyle(lineWidth: 5.8, lineCap: .round)
                )
            }
        }
    }
}

private struct RecordingHUDView: View {
    @ObservedObject var state: RecordingHUDState
    @StateObject private var animationViewModel = NotchAnimationViewModel()

    private var notchGlow: NotchGlow {
        NotchGlow(
            centerX: state.metrics.notchRect.midX,
            centerY: state.metrics.bandHeight / 2,
            coreRadius: min(64, state.metrics.notchRect.width * 0.44),
            haloRadius: min(140, state.metrics.notchRect.width * 0.95)
        )
    }

    var body: some View {
        Group {
            if state.isVisible {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 18, height: 4)

                    Circle()
                        .fill(Color(red: 0.54, green: 1.0, blue: 0.80))
                        .frame(width: 7, height: 7)
                        .scaleEffect(isVisiblePulse ? 1.0 : 0.68)

                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 18, height: 4)
                }
                .frame(width: max(72, state.metrics.notchRect.width * 0.42), height: max(14, state.metrics.bandHeight * 0.34))
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.18))
                )
            } else {
                Color.clear
            }
        }
        .frame(width: state.metrics.panelFrame.width, height: state.metrics.bandHeight)
        .onChange(of: state.isVisible) { _, isVisible in
            if isVisible {
                animationViewModel.start(metrics: state.metrics)
            } else {
                animationViewModel.stop()
            }
        }
        .onChange(of: state.metrics) { _, metrics in
            if state.isVisible {
                animationViewModel.start(metrics: metrics)
            }
        }
        .onAppear {
            isVisiblePulse = true
        }
    }

    @State private var isVisiblePulse = false
}

final class RecordingHUDController {
    private var panel: NSPanel?
    private let state = RecordingHUDState()

    func show() {
        guard let screen = currentScreen() else { return }
        let metrics = NotchHUDMetrics.forScreen(screen)
        ensurePanel(for: metrics)
        guard let panel else { return }

        state.metrics = metrics
        position(panel: panel, metrics: metrics)
        panel.orderFrontRegardless()

        withAnimation(.easeOut(duration: 0.16)) {
            state.isVisible = true
        }
    }

    func hide(immediately: Bool = false) {
        guard let panel else { return }

        let finishHide = { [weak self] in
            self?.state.isVisible = false
            panel.orderOut(nil)
        }

        if immediately {
            finishHide()
            return
        }

        withAnimation(.easeOut(duration: 0.14)) {
            state.isVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            if !self.state.isVisible {
                panel.orderOut(nil)
            }
        }
    }

    private func ensurePanel(for metrics: NotchHUDMetrics) {
        if let panel {
            panel.setContentSize(metrics.panelFrame.size)
            return
        }

        let hosting = NSHostingView(rootView: RecordingHUDView(state: state))
        let panel = NSPanel(
            contentRect: metrics.panelFrame,
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

    private func position(panel: NSPanel, metrics: NotchHUDMetrics) {
        panel.setFrame(metrics.panelFrame, display: false)
    }

    private func currentScreen() -> NSScreen? {
        NSApp.keyWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
