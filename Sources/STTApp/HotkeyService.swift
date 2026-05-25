import AppKit

@MainActor
final class HotkeyService {
    typealias Handler = (DictationProfile) -> Void
    typealias TrainingHandler = () -> Void

    private let onStart: Handler
    private let onStop: Handler
    private let onTrainingToggle: TrainingHandler
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var activeProfile: DictationProfile?
    private var pendingMixedStart: Task<Void, Never>?
    private var lastControlTapDate: Date?
    private var controlWasDown = false

    init(onStart: @escaping Handler, onStop: @escaping Handler, onTrainingToggle: @escaping TrainingHandler) {
        self.onStart = onStart
        self.onStop = onStop
        self.onTrainingToggle = onTrainingToggle
    }

    func start() {
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
            return event
        }
    }

    func stop() {
        pendingMixedStart?.cancel()
        [globalFlagsMonitor, localFlagsMonitor].compactMap { $0 }.forEach {
            NSEvent.removeMonitor($0)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        handleTrainingControlTap(flags: flags)
        let profile = profile(for: flags)

        if let activeProfile {
            guard profile == activeProfile else {
                pendingMixedStart?.cancel()
                self.activeProfile = nil
                onStop(activeProfile)

                if profile == .hebrew {
                    startImmediately(.hebrew)
                } else if profile == .mixedRuEn {
                    scheduleMixedStart()
                }
                return
            }
            return
        }

        pendingMixedStart?.cancel()
        switch profile {
        case .hebrew:
            startImmediately(.hebrew)
        case .mixedRuEn:
            scheduleMixedStart()
        case nil:
            break
        }
    }

    private func startImmediately(_ profile: DictationProfile) {
        pendingMixedStart?.cancel()
        activeProfile = profile
        onStart(profile)
    }

    private func scheduleMixedStart() {
        pendingMixedStart = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            await MainActor.run {
                guard let self, self.activeProfile == nil else { return }
                guard Self.profile(for: NSEvent.modifierFlags) == .mixedRuEn else { return }
                self.startImmediately(.mixedRuEn)
            }
        }
    }

    private static func profile(for flags: NSEvent.ModifierFlags) -> DictationProfile? {
        guard flags.contains(.function), flags.contains(.shift) else { return nil }
        if flags.contains(.control) {
            return .hebrew
        }
        return .mixedRuEn
    }

    private func profile(for flags: NSEvent.ModifierFlags) -> DictationProfile? {
        Self.profile(for: flags)
    }

    private func handleTrainingControlTap(flags: NSEvent.ModifierFlags) {
        let isControlOnly = flags == .control
        if isControlOnly, !controlWasDown {
            let now = Date()
            if let lastControlTapDate, now.timeIntervalSince(lastControlTapDate) <= 0.38 {
                self.lastControlTapDate = nil
                onTrainingToggle()
            } else {
                lastControlTapDate = now
            }
        }
        controlWasDown = isControlOnly
        if !flags.isEmpty, !isControlOnly {
            lastControlTapDate = nil
        }
    }
}
