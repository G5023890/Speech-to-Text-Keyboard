import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import QuartzCore
import ServiceManagement
import SwiftUI

enum HotkeyMode: String, CaseIterable {
    case shiftOption
    case shiftControl
    case shiftCommand
    case shiftFn
    case fn

    var title: String {
        switch self {
        case .shiftOption:
            return "Shift+Option"
        case .shiftControl:
            return "Shift+Control"
        case .shiftCommand:
            return "Shift+Command"
        case .shiftFn:
            return "Shift+Fn"
        case .fn:
            return "Fn"
        }
    }

    func isPressed(flags: NSEvent.ModifierFlags) -> Bool {
        switch self {
        case .shiftOption:
            return flags.contains(.shift) && flags.contains(.option)
        case .shiftControl:
            return flags.contains(.shift) && flags.contains(.control)
        case .shiftCommand:
            return flags.contains(.shift) && flags.contains(.command)
        case .shiftFn:
            return flags.contains(.shift) && flags.contains(.function)
        case .fn:
            return flags.contains(.function)
        }
    }
}

enum TranscribeModel: String, CaseIterable {
    case mediumQ5
    case smallQ5
    case largeV3TurboQ5

    var title: String {
        switch self {
        case .mediumQ5:
            return "medium-q5_0"
        case .smallQ5:
            return "small-q5_1"
        case .largeV3TurboQ5:
            return "large-v3-turbo-q5_0"
        }
    }

    var fileName: String {
        switch self {
        case .mediumQ5:
            return "ggml-medium-q5_0.bin"
        case .smallQ5:
            return "ggml-small-q5_1.bin"
        case .largeV3TurboQ5:
            return "ggml-large-v3-turbo-q5_0.bin"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct ClipboardSnapshot {
        let items: [[String: Data]]
    }

    private struct ClipboardRestoreState {
        let snapshot: ClipboardSnapshot
        let expectedChangeCount: Int
        let injectedText: String
    }

    private struct UsageBucket: Codable {
        var sessions: Int = 0
        var seconds: Double = 0
        var characters: Int = 0
    }

    private struct UsageStats: Codable {
        var total: UsageBucket = .init()
        var daily: [String: UsageBucket] = [:]
    }

    private let appSupportSubdir = "Voice Input"

    private var statusItem: NSStatusItem?
    private var menuBarIconImage: NSImage?
    private var loadingIndicator: NSProgressIndicator?
    private var recordingHaloWindow: NSWindow?
    private var recordingHaloLayer: CAShapeLayer?
    private var recordingHaloHighlightLayer: CAShapeLayer?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isRecording = false
    private var recordingStartedAt: Date?
    private var recorder: AVAudioRecorder?
    private var hotkeyMenuItems: [HotkeyMode: NSMenuItem] = [:]
    private var transcribeModelMenuItems: [TranscribeModel: NSMenuItem] = [:]
    private var launchAtLoginItem: NSMenuItem?
    private var checkUpdatesItem: NSMenuItem?
    private var modelsStatusItem: NSMenuItem?
    private var modelsVersionItem: NSMenuItem?
    private var modelsUpdateStateItem: NSMenuItem?
    private var modelsProgressItem: NSMenuItem?
    private var modelUpdateItem: NSMenuItem?
    private var statsTodayItem: NSMenuItem?
    private var statsWeekItem: NSMenuItem?
    private var statsMonthItem: NSMenuItem?
    private var statsTotalItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var settingsViewModel: SettingsViewModel?
    private let hotkeyDefaultsKey = "voice_input_hotkey_mode"
    private let transcribeModelDefaultsKey = "voice_input_transcribe_model"
    private let launchAtLoginDefaultsKey = "voice_input_launch_at_login"
    private var hotkeyMode: HotkeyMode = .shiftOption
    private var transcribeModel: TranscribeModel = .mediumQ5
    private var modelUpdateInProgress = false
    private var updateCheckInProgress = false
    private var modelUpdateAvailable = false
    private var activityCounter = 0
    private var clipboardRestoreState: ClipboardRestoreState?
    private var usageStats = UsageStats()
    private var lastAcceptedTranscript: String = ""
    private let managedModels = ["ggml-medium-q5_0.bin", "ggml-small-q5_1.bin", "ggml-large-v3-turbo-q5_0.bin"]
    private let legacyManagedModels = ["ggml-medium-q5_0.bin", "ggml-small-q5_1.bin", "ggml-large-v3-turbo-q5_0.bin", "ggml-medium.bin", "ggml-small.bin"]
    private let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ensureModelsDirectoryReady()
        loadUsageStats()
        loadHotkeyMode()
        loadTranscribeModel()
        setupStatusItem()
        ensureAccessibilityPermission()
        ensureMicrophonePermission { _ in }
        setupHotkeyMonitors()
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title)")
    }

    private var appSupportDirectoryPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportSubdir, isDirectory: true).path
    }

    private var modelsDirectoryPath: String {
        return "\(appSupportDirectoryPath)/models"
    }

    private var legacyModelsDirectoryPath: String {
        return "\(NSHomeDirectory())/Documents/Develop/Voice input/models"
    }

    private var runtimeDirectoryPath: String {
        return "\(appSupportDirectoryPath)/.runtime"
    }

    private var recordingPath: String {
        return "\(runtimeDirectoryPath)/ptt_input.wav"
    }

    private var usageStatsFilePath: String {
        return "\(appSupportDirectoryPath)/usage_stats.json"
    }

    private var transcriptionDiagnosticsPath: String {
        return "\(appSupportDirectoryPath)/transcription_diagnostics.log"
    }

    private var transcribeScriptPath: String? {
        if let bundled = Bundle.main.path(forResource: "ptt_whisper", ofType: "sh"),
           FileManager.default.isExecutableFile(atPath: bundled)
        {
            return bundled
        }
        let local = "\(FileManager.default.currentDirectoryPath)/scripts/ptt_whisper.sh"
        if FileManager.default.isExecutableFile(atPath: local) {
            return local
        }
        return nil
    }

    private func ensureModelsDirectoryReady() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: appSupportDirectoryPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: modelsDirectoryPath, withIntermediateDirectories: true)

        for model in legacyManagedModels {
            let newPath = "\(modelsDirectoryPath)/\(model)"
            if fileManager.fileExists(atPath: newPath) {
                continue
            }
            let oldPath = "\(legacyModelsDirectoryPath)/\(model)"
            if fileManager.fileExists(atPath: oldPath) {
                try? fileManager.copyItem(atPath: oldPath, toPath: newPath)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopRecordingHalo()
        if let globalFlagsMonitor {
            NSEvent.removeMonitor(globalFlagsMonitor)
        }
        if let localFlagsMonitor {
            NSEvent.removeMonitor(localFlagsMonitor)
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            if let image = loadMenuBarIcon() {
                image.size = NSSize(width: 16.2, height: 16.2)
                image.isTemplate = true
                menuBarIconImage = image
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.title = "Mic"
            }
            button.toolTip = "Voice Input"

            let indicator = NSProgressIndicator()
            indicator.style = .spinning
            indicator.controlSize = .small
            indicator.isIndeterminate = true
            indicator.isDisplayedWhenStopped = false
            indicator.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                indicator.centerYAnchor.constraint(equalTo: button.centerYAnchor)
            ])
            loadingIndicator = indicator
        }

        prepareSettingsStateItems()

        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Настройки…", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Voice Input", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    private func prepareSettingsStateItems() {
        hotkeyMenuItems.removeAll()
        transcribeModelMenuItems.removeAll()

        let launchItem = NSMenuItem(title: "Запуск при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchAtLoginItem = launchItem

        for mode in HotkeyMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.isEnabled = true
            hotkeyMenuItems[mode] = item
        }

        for model in TranscribeModel.allCases {
            let item = NSMenuItem(title: model.title, action: #selector(selectTranscribeModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.rawValue
            item.isEnabled = true
            transcribeModelMenuItems[model] = item
        }

        let checkItem = NSMenuItem(title: "Проверить обновления", action: #selector(checkForUpdatesPressed), keyEquivalent: "u")
        checkItem.target = self
        checkItem.isEnabled = true
        checkUpdatesItem = checkItem

        let mStatus = NSMenuItem(title: "Модели: не проверено", action: nil, keyEquivalent: "")
        mStatus.isEnabled = false
        modelsStatusItem = mStatus

        let mVersion = NSMenuItem(title: "Версии моделей: —", action: nil, keyEquivalent: "")
        mVersion.isEnabled = false
        modelsVersionItem = mVersion

        let mUpdateState = NSMenuItem(title: "Обновление моделей: —", action: nil, keyEquivalent: "")
        mUpdateState.isEnabled = false
        modelsUpdateStateItem = mUpdateState

        let mProgress = NSMenuItem(title: "Прогресс обновления: —", action: nil, keyEquivalent: "")
        mProgress.isEnabled = false
        mProgress.isHidden = true
        modelsProgressItem = mProgress

        let modelItem = NSMenuItem(title: "Обновить модели", action: #selector(confirmAndUpdateModels), keyEquivalent: "")
        modelItem.target = self
        modelItem.isEnabled = false
        modelUpdateItem = modelItem

        let todayItem = NSMenuItem(title: "Сегодня: —", action: nil, keyEquivalent: "")
        todayItem.isEnabled = false
        statsTodayItem = todayItem

        let weekItem = NSMenuItem(title: "Неделя: —", action: nil, keyEquivalent: "")
        weekItem.isEnabled = false
        statsWeekItem = weekItem

        let monthItem = NSMenuItem(title: "Месяц: —", action: nil, keyEquivalent: "")
        monthItem.isEnabled = false
        statsMonthItem = monthItem

        let totalItem = NSMenuItem(title: "Всего: —", action: nil, keyEquivalent: "")
        totalItem.isEnabled = false
        statsTotalItem = totalItem

        updateLaunchAtLoginMenuState()
        updateHotkeyMenuState()
        updateTranscribeModelMenuState()
        updateUsageStatsMenuState()
    }

    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            settingsWindow = buildSettingsWindow()
            settingsWindow?.center()
        }
        settingsViewModel?.reload()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildSettingsWindow() -> NSWindow {
        let viewModel = SettingsViewModel(actions: makeSettingsActions())
        let view = SettingsView(viewModel: viewModel)
        let hostingController = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 720, height: 640))
        window.title = "Настройки"
        window.isReleasedWhenClosed = false
        settingsViewModel = viewModel
        return window
    }

    private func refreshSettingsWindow() {
        settingsViewModel?.reload()
    }

    private func makeSettingsActions() -> SettingsActions {
        return SettingsActions(
            snapshot: { [weak self] in
                return self?.currentSettingsSnapshot() ?? .mock
            },
            setLaunchAtLogin: { [weak self] enabled in
                self?.setLaunchAtLogin(enabled)
            },
            setHotkey: { [weak self] rawValue in
                self?.setHotkey(rawValue: rawValue)
            },
            setModel: { [weak self] rawValue in
                self?.setTranscribeModel(rawValue: rawValue)
            },
            checkUpdates: { [weak self] completion in
                guard let self else {
                    completion(.mock)
                    return
                }
                self.checkForUpdates { snapshot in
                    completion(snapshot)
                }
            },
            updateModels: { [weak self] completion in
                guard let self else {
                    completion(.mock)
                    return
                }
                self.updateModels { snapshot in
                    completion(snapshot)
                }
            },
            resetStats: { [weak self] in
                self?.resetUsageStatsData()
            }
        )
    }

    private func installedModelsCount() -> Int {
        managedModels.reduce(into: 0) { result, model in
            if FileManager.default.fileExists(atPath: "\(modelsDirectoryPath)/\(model)") {
                result += 1
            }
        }
    }

    private func currentSettingsSnapshot() -> SettingsSnapshot {
        let today = usageForLastDays(1)
        let week = usageForCurrentWeek()
        let month = usageForCurrentMonth()
        let weekHasAggregate = week.sessions > today.sessions || week.characters > today.characters || week.seconds > today.seconds + 0.001
        let monthHasAggregate = month.sessions > today.sessions || month.characters > today.characters || month.seconds > today.seconds + 0.001
        let totalHasAggregate = usageStats.total.sessions > today.sessions || usageStats.total.characters > today.characters || usageStats.total.seconds > today.seconds + 0.001
        let stats = SettingsStats(
            todaySeconds: today.seconds,
            weekSeconds: week.seconds,
            monthSeconds: month.seconds,
            totalSeconds: usageStats.total.seconds,
            sessions: usageStats.total.sessions,
            characters: usageStats.total.characters,
            hasWeeklyAggregate: weekHasAggregate,
            hasMonthlyAggregate: monthHasAggregate,
            hasTotalAggregate: totalHasAggregate
        )
        return SettingsSnapshot(
            launchAtLoginEnabled: isLaunchAtLoginEnabled(),
            selectedHotkey: hotkeyMode.rawValue,
            selectedModelID: transcribeModel.rawValue,
            installedModelCount: installedModelsCount(),
            totalModelCount: managedModels.count,
            updatesAvailable: modelUpdateAvailable,
            lastCheckStatus: settingsLastCheckStatusText(),
            stats: stats,
            isCheckingUpdates: updateCheckInProgress,
            isUpdatingModels: modelUpdateInProgress
        )
    }

    private func settingsLastCheckStatusText() -> String {
        if modelUpdateInProgress {
            return modelsProgressItem?.title ?? "Идет обновление моделей…"
        }
        if updateCheckInProgress {
            return "Проверяем обновления…"
        }
        if let state = modelsUpdateStateItem?.title, state != "Обновление моделей: —" {
            return "Последняя проверка: \(state.replacingOccurrences(of: "Обновление моделей: ", with: ""))"
        }
        return "Проверка обновлений еще не выполнялась"
    }

    private func loadMenuBarIcon() -> NSImage? {
        if let bundlePath = Bundle.main.path(forResource: "taskbar_Mic", ofType: "png"),
           let image = NSImage(contentsOfFile: bundlePath)
        {
            return image
        }
        return nil
    }

    private func setupHotkeyMonitors() {
        let flagsHandler: (NSEvent) -> Void = { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler)
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event.modifierFlags)
            return event
        }
    }

    private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
        let hotkeyHeld = hotkeyMode.isPressed(flags: flags)
        if hotkeyHeld && !isRecording {
            startRecording()
            return
        }
        if !hotkeyHeld && isRecording {
            stopRecordingAndPaste()
        }
    }

    private func loadHotkeyMode() {
        let saved = UserDefaults.standard.string(forKey: hotkeyDefaultsKey) ?? HotkeyMode.shiftOption.rawValue
        hotkeyMode = HotkeyMode(rawValue: saved) ?? .shiftOption
    }

    private func saveHotkeyMode() {
        UserDefaults.standard.set(hotkeyMode.rawValue, forKey: hotkeyDefaultsKey)
    }

    private func loadTranscribeModel() {
        let saved = UserDefaults.standard.string(forKey: transcribeModelDefaultsKey) ?? TranscribeModel.mediumQ5.rawValue
        transcribeModel = TranscribeModel(rawValue: saved) ?? .mediumQ5
    }

    private func saveTranscribeModel() {
        UserDefaults.standard.set(transcribeModel.rawValue, forKey: transcribeModelDefaultsKey)
    }

    private func loadUsageStats() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: appSupportDirectoryPath, withIntermediateDirectories: true)
        guard let data = fileManager.contents(atPath: usageStatsFilePath) else {
            usageStats = UsageStats()
            return
        }
        do {
            usageStats = try JSONDecoder().decode(UsageStats.self, from: data)
        } catch {
            usageStats = UsageStats()
        }
        pruneUsageStats(keepingLastDays: 400)
    }

    private func saveUsageStats() {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: appSupportDirectoryPath, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder().encode(usageStats)
            try data.write(to: URL(fileURLWithPath: usageStatsFilePath), options: .atomic)
        } catch {
            // Keep app flow uninterrupted if stats persistence fails.
        }
    }

    private func dayKey(for date: Date) -> String {
        return dayKeyFormatter.string(from: date)
    }

    private func dateFromDayKey(_ key: String) -> Date? {
        return dayKeyFormatter.date(from: key)
    }

    private func usageForLastDays(_ days: Int) -> UsageBucket {
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(for: Date()).addingTimeInterval(Double(-(days - 1)) * 86_400.0)
        var bucket = UsageBucket()
        for (day, value) in usageStats.daily {
            guard let date = dateFromDayKey(day) else {
                continue
            }
            if date >= cutoff {
                bucket.sessions += value.sessions
                bucket.seconds += value.seconds
                bucket.characters += value.characters
            }
        }
        return bucket
    }

    private func usageForCurrentWeek() -> UsageBucket {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return UsageBucket()
        }
        var bucket = UsageBucket()
        for (day, value) in usageStats.daily {
            guard let date = dateFromDayKey(day) else {
                continue
            }
            if interval.contains(date) {
                bucket.sessions += value.sessions
                bucket.seconds += value.seconds
                bucket.characters += value.characters
            }
        }
        return bucket
    }

    private func usageForCurrentMonth() -> UsageBucket {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: Date()) else {
            return UsageBucket()
        }
        var bucket = UsageBucket()
        for (day, value) in usageStats.daily {
            guard let date = dateFromDayKey(day) else {
                continue
            }
            if interval.contains(date) {
                bucket.sessions += value.sessions
                bucket.seconds += value.seconds
                bucket.characters += value.characters
            }
        }
        return bucket
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours)ч \(minutes)м \(secs)с"
        }
        if minutes > 0 {
            return "\(minutes)м \(secs)с"
        }
        return "\(secs)с"
    }

    private func formatUsageBucket(_ bucket: UsageBucket) -> String {
        return "\(formatDuration(bucket.seconds)), \(bucket.sessions) дикт., \(bucket.characters) симв."
    }

    private func updateUsageStatsMenuState() {
        let today = usageForLastDays(1)
        let week = usageForCurrentWeek()
        let month = usageForCurrentMonth()
        statsTodayItem?.title = "Сегодня: \(formatUsageBucket(today))"
        statsWeekItem?.title = "Неделя: \(formatUsageBucket(week))"
        statsMonthItem?.title = "Месяц: \(formatUsageBucket(month))"
        statsTotalItem?.title = "Всего: \(formatUsageBucket(usageStats.total))"
        refreshSettingsWindow()
    }

    private func recordUsage(durationSeconds: Double, text: String) {
        let seconds = max(0.0, durationSeconds)
        let chars = text.count
        guard seconds > 0 || chars > 0 else {
            return
        }

        let key = dayKey(for: Date())
        var day = usageStats.daily[key] ?? UsageBucket()
        day.sessions += 1
        day.seconds += seconds
        day.characters += chars
        usageStats.daily[key] = day

        usageStats.total.sessions += 1
        usageStats.total.seconds += seconds
        usageStats.total.characters += chars

        pruneUsageStats(keepingLastDays: 400)
        saveUsageStats()
        updateUsageStatsMenuState()
    }

    private func pruneUsageStats(keepingLastDays days: Int) {
        let calendar = Calendar.current
        let cutoff = calendar.startOfDay(for: Date()).addingTimeInterval(Double(-days) * 86_400.0)
        usageStats.daily = usageStats.daily.filter { key, _ in
            guard let date = dateFromDayKey(key) else {
                return false
            }
            return date >= cutoff
        }
    }

    private func countWords(_ text: String) -> Int {
        return text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private func normalizeTranscript(_ text: String) -> String {
        return text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func shouldRejectTranscript(_ text: String, durationSeconds: Double) -> (reject: Bool, reason: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return (true, "empty")
        }

        let seconds = max(0.0, durationSeconds)
        let words = countWords(trimmed)
        let chars = trimmed.count
        let charsPerSecond = Double(chars) / max(seconds, 0.2)

        if seconds < 0.16 {
            return (true, "too_short_audio")
        }
        if seconds < 0.60 && (words >= 5 || chars >= 28) {
            return (true, "short_audio_long_text")
        }
        if seconds < 1.20 && (words >= 12 || chars >= 90) {
            return (true, "very_dense_text")
        }
        if charsPerSecond > 35.0 {
            return (true, "unrealistic_speed")
        }

        let normalized = normalizeTranscript(trimmed)
        if !lastAcceptedTranscript.isEmpty, normalized == normalizeTranscript(lastAcceptedTranscript), seconds < 0.9 {
            return (true, "repeat_from_previous_short_audio")
        }

        return (false, "ok")
    }

    private func appendTranscriptionDiagnostic(status: String, durationSeconds: Double, text: String, reason: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: appSupportDirectoryPath, withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let compactText = text.replacingOccurrences(of: "\n", with: " ").prefix(200)
        let line = "\(timestamp)\t\(status)\t\(String(format: "%.2f", durationSeconds))s\t\(reason)\t\(compactText)\n"

        if !fileManager.fileExists(atPath: transcriptionDiagnosticsPath) {
            try? line.write(to: URL(fileURLWithPath: transcriptionDiagnosticsPath), atomically: true, encoding: .utf8)
            return
        }

        if let handle = FileHandle(forWritingAtPath: transcriptionDiagnosticsPath) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                try? handle.write(contentsOf: data)
            }
        }
    }

    private func updateHotkeyMenuState() {
        for (mode, item) in hotkeyMenuItems {
            item.state = (mode == hotkeyMode) ? .on : .off
        }
        refreshSettingsWindow()
    }

    private func updateTranscribeModelMenuState() {
        for (model, item) in transcribeModelMenuItems {
            item.state = (model == transcribeModel) ? .on : .off
        }
        refreshSettingsWindow()
    }

    private func updateLaunchAtLoginMenuState() {
        guard let launchAtLoginItem else {
            return
        }
        var launchEnabled = false
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                launchAtLoginItem.state = .on
                launchEnabled = true
            case .requiresApproval:
                launchAtLoginItem.state = .mixed
                launchEnabled = true
            default:
                launchAtLoginItem.state = .off
            }
        } else {
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = false
        }
        UserDefaults.standard.set(launchEnabled, forKey: launchAtLoginDefaultsKey)
        refreshSettingsWindow()
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled, .requiresApproval:
                return true
            default:
                return false
            }
        }
        return false
    }

    private func ensureAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func ensureMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }

    private func startRecording() {
        ensureMicrophonePermission { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.showStatus("Microphone permission denied")
                return
            }
            self.beginNativeRecording()
        }
    }

    private func beginNativeRecording() {
        if isRecording {
            return
        }
        isRecording = true
        recordingStartedAt = Date()
        startRecordingHalo()
        showStatus("Recording...")

        let runtimeDir = runtimeDirectoryPath
        try? FileManager.default.createDirectory(atPath: runtimeDir, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(atPath: recordingPath)

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false
        ]

        do {
            recorder = try AVAudioRecorder(url: URL(fileURLWithPath: recordingPath), settings: settings)
            recorder?.prepareToRecord()
            if recorder?.record() != true {
                isRecording = false
                recordingStartedAt = nil
                stopRecordingHalo()
                showStatus("Failed to start recording")
            }
        } catch {
            isRecording = false
            recordingStartedAt = nil
            stopRecordingHalo()
            showStatus("Recorder error")
        }
    }

    private func stopRecordingAndPaste() {
        if !isRecording {
            return
        }
        isRecording = false
        stopRecordingHalo()
        let recorderDuration = max(0.0, recorder?.currentTime ?? 0.0)
        let fallbackDuration = max(0.0, Date().timeIntervalSince(recordingStartedAt ?? Date()))
        let sessionDuration = recorderDuration > 0.0 ? recorderDuration : fallbackDuration
        recorder?.stop()
        recorder = nil
        recordingStartedAt = nil

        if sessionDuration < 0.12 {
            appendTranscriptionDiagnostic(
                status: "rejected",
                durationSeconds: sessionDuration,
                text: "",
                reason: "too_short_before_transcribe"
            )
            showStatus("No speech detected")
            clearTransientData(clearClipboard: false)
            return
        }
        showStatus("Transcribing...")

        runTranscribe(audioPath: recordingPath) { [weak self] exitCode, output, errorText in
            guard let self else { return }
            guard exitCode == 0 else {
                self.appendTranscriptionDiagnostic(
                    status: "rejected",
                    durationSeconds: sessionDuration,
                    text: "",
                    reason: "stt_error_\(exitCode)"
                )
                self.showStatus("STT error")
                self.showErrorAlert(title: "STT error", text: errorText.isEmpty ? "Transcription failed." : errorText)
                self.clearTransientData(clearClipboard: false)
                return
            }

            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                self.appendTranscriptionDiagnostic(
                    status: "rejected",
                    durationSeconds: sessionDuration,
                    text: text,
                    reason: "empty_output"
                )
                self.showStatus("No speech detected")
                self.clearTransientData(clearClipboard: false)
                return
            }

            let decision = self.shouldRejectTranscript(text, durationSeconds: sessionDuration)
            if decision.reject {
                self.appendTranscriptionDiagnostic(
                    status: "rejected",
                    durationSeconds: sessionDuration,
                    text: text,
                    reason: decision.reason
                )
                self.showStatus("Артефакт распознавания (пропущено)")
                self.clearTransientData(clearClipboard: false)
                return
            }

            self.lastAcceptedTranscript = text
            self.appendTranscriptionDiagnostic(
                status: "accepted",
                durationSeconds: sessionDuration,
                text: text,
                reason: "ok"
            )

            self.recordUsage(durationSeconds: sessionDuration, text: text)

            let pasted = self.pasteText(text)
            if pasted {
                self.showStatus("Pasted")
                self.clearTransientData(clearClipboard: true)
            } else {
                self.showStatus("Paste blocked, text copied")
                self.clearTransientData(clearClipboard: false)
                self.showErrorAlert(title: "Auto-paste blocked", text: "Text is copied to clipboard. Grant Accessibility for Voice Input to allow auto-paste.")
            }
        }
    }

    private func runTranscribe(audioPath: String, completion: @escaping (Int32, String, String) -> Void) {
        guard let scriptPath = transcribeScriptPath else {
            completion(1, "", "Transcription script not found.")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        let quotedScript = "\"\(scriptPath)\""
        let quotedAudio = "\"\(audioPath)\""
        process.arguments = ["-lc", "\(quotedScript) transcribe \(quotedAudio)"]
        var env = ProcessInfo.processInfo.environment
        env["WHISPER_MODEL_DIR"] = modelsDirectoryPath
        env["WHISPER_MODEL"] = "\(modelsDirectoryPath)/\(transcribeModel.fileName)"
        env["WHISPER_APP_SUPPORT_DIR"] = appSupportDirectoryPath
        env["WHISPER_RUNTIME_DIR"] = runtimeDirectoryPath
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        process.terminationHandler = { proc in
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""
            let errorOutput = String(data: errData, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                completion(proc.terminationStatus, output, errorOutput)
            }
        }

        do {
            try process.run()
        } catch {
            completion(1, "", "Cannot launch transcription process.")
        }
    }

    private func pasteText(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }
        let board = NSPasteboard.general
        let snapshot = snapshotClipboard(board)
        board.clearContents()
        board.setString(text, forType: .string)
        clipboardRestoreState = ClipboardRestoreState(snapshot: snapshot, expectedChangeCount: board.changeCount, injectedText: text)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        cmdDown?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        cmdUp?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        return true
    }

    private func snapshotClipboard(_ board: NSPasteboard) -> ClipboardSnapshot {
        let items = (board.pasteboardItems ?? []).map { item in
            var map: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    map[type.rawValue] = data
                }
            }
            return map
        }
        return ClipboardSnapshot(items: items)
    }

    private func restoreClipboardIfNeeded() {
        guard let state = clipboardRestoreState else {
            return
        }
        let board = NSPasteboard.general
        defer { clipboardRestoreState = nil }

        // If user/app changed clipboard after our auto-paste, do not overwrite it.
        guard board.changeCount == state.expectedChangeCount else {
            return
        }
        let currentText = board.string(forType: .string) ?? ""
        guard currentText == state.injectedText else {
            return
        }

        board.clearContents()
        if state.snapshot.items.isEmpty {
            return
        }

        let restoredItems: [NSPasteboardItem] = state.snapshot.items.map { saved in
            let item = NSPasteboardItem()
            for (typeRaw, data) in saved {
                item.setData(data, forType: NSPasteboard.PasteboardType(typeRaw))
            }
            return item
        }
        board.writeObjects(restoredItems)
    }

    private func clearTransientData(clearClipboard: Bool) {
        let runtimeDir = runtimeDirectoryPath
        try? FileManager.default.removeItem(atPath: "\(runtimeDir)/ptt_input.txt")
        try? FileManager.default.removeItem(atPath: "\(runtimeDir)/ptt_input.wav")
        try? FileManager.default.removeItem(atPath: "\(runtimeDir)/recording.pid")
        if clearClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.restoreClipboardIfNeeded()
            }
        } else {
            clipboardRestoreState = nil
        }
    }

    private func showStatus(_ text: String) {
        if let button = statusItem?.button {
            button.toolTip = "Voice Input - \(text)"
        }
    }

    private func startRecordingHalo() {
        return
    }

    private func stopRecordingHalo() {
        recordingHaloLayer?.removeAllAnimations()
        recordingHaloHighlightLayer?.removeAllAnimations()
        recordingHaloLayer = nil
        recordingHaloHighlightLayer = nil
        recordingHaloWindow?.orderOut(nil)
        recordingHaloWindow = nil
    }

    private func beginActivity() {
        activityCounter += 1
        updateMenuBarLoadingState()
    }

    private func endActivity() {
        activityCounter = max(0, activityCounter - 1)
        updateMenuBarLoadingState()
    }

    private func updateMenuBarLoadingState() {
        guard let button = statusItem?.button else {
            return
        }
        let isLoading = activityCounter > 0
        if isLoading {
            button.image = nil
            button.title = ""
            loadingIndicator?.startAnimation(nil)
            return
        }

        loadingIndicator?.stopAnimation(nil)
        if let image = menuBarIconImage {
            button.title = ""
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = "Mic"
        }
    }

    private func setModelProgress(_ percent: Int, detail: String) {
        modelsProgressItem?.isHidden = false
        modelsProgressItem?.title = "Прогресс обновления: \(percent)% (\(detail))"
        refreshSettingsWindow()
    }

    private func clearModelProgress() {
        modelsProgressItem?.isHidden = true
        modelsProgressItem?.title = "Прогресс обновления: —"
        refreshSettingsWindow()
    }

    private func showErrorAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func updateModels(completion: ((SettingsSnapshot) -> Void)? = nil) {
        if modelUpdateInProgress {
            completion?(currentSettingsSnapshot())
            return
        }
        modelUpdateInProgress = true
        modelUpdateItem?.isEnabled = false
        refreshSettingsWindow()
        beginActivity()
        setModelProgress(0, detail: "старт")
        showStatus("Updating models...")

        guard let scriptPath = transcribeScriptPath else {
            modelUpdateInProgress = false
            modelUpdateItem?.isEnabled = false
            refreshSettingsWindow()
            clearModelProgress()
            endActivity()
            showStatus("Model update failed")
            showErrorAlert(title: "Model update failed", text: "Update script not found.")
            completion?(self.currentSettingsSnapshot())
            return
        }
        let scriptEnv = [
            "WHISPER_MODEL_DIR": modelsDirectoryPath,
            "WHISPER_APP_SUPPORT_DIR": "\(NSHomeDirectory())/Library/Application Support/\(appSupportSubdir)",
            "WHISPER_RUNTIME_DIR": runtimeDirectoryPath
        ]
        let turboCommand = """
        "\(scriptPath)" download-turbo-model
        """
        runShell(command: turboCommand, environment: scriptEnv) { [weak self] firstCode, firstOutput in
            guard let self else { return }
            guard firstCode == 0 else {
                self.modelUpdateInProgress = false
                self.modelUpdateItem?.isEnabled = false
                self.refreshSettingsWindow()
                self.clearModelProgress()
                self.endActivity()
                self.showStatus("Model update failed")
                let alert = NSAlert()
                alert.messageText = "Model update failed"
                alert.informativeText = firstOutput.isEmpty ? "Check internet connection and try again." : firstOutput
                alert.alertStyle = .warning
                alert.runModal()
                self.checkForUpdates(completion: completion)
                return
            }
            self.setModelProgress(33, detail: "small-q5_1")

            let fastCommand = """
            "\(scriptPath)" download-fast-model
            """
            self.runShell(command: fastCommand, environment: scriptEnv) { [weak self] secondCode, secondOutput in
                guard let self else { return }

                guard secondCode == 0 else {
                    self.modelUpdateInProgress = false
                    self.modelUpdateItem?.isEnabled = false
                    self.refreshSettingsWindow()
                    self.clearModelProgress()
                    self.endActivity()
                    self.showStatus("Model update failed")
                    let alert = NSAlert()
                    alert.messageText = "Model update failed"
                    alert.informativeText = secondOutput.isEmpty ? "Check internet connection and try again." : secondOutput
                    alert.alertStyle = .warning
                    alert.runModal()
                    self.checkForUpdates(completion: completion)
                    return
                }

                self.setModelProgress(66, detail: "medium-q5_0")
                let largeCommand = """
                "\(scriptPath)" download-large-v3-turbo-model
                """
                self.runShell(command: largeCommand, environment: scriptEnv) { [weak self] thirdCode, thirdOutput in
                    guard let self else { return }
                    self.modelUpdateInProgress = false
                    self.endActivity()

                    guard thirdCode == 0 else {
                        self.modelUpdateItem?.isEnabled = false
                        self.refreshSettingsWindow()
                        self.clearModelProgress()
                        self.showStatus("Model update failed")
                        let alert = NSAlert()
                        alert.messageText = "Model update failed"
                        alert.informativeText = thirdOutput.isEmpty ? "Check internet connection and try again." : thirdOutput
                        alert.alertStyle = .warning
                        alert.runModal()
                        self.checkForUpdates(completion: completion)
                        return
                    }

                    self.setModelProgress(100, detail: "large-v3-turbo-q5_0")
                    self.modelUpdateItem?.isEnabled = false
                    self.refreshSettingsWindow()
                    self.showStatus("Models updated")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.clearModelProgress()
                        self?.checkForUpdates(completion: completion)
                    }
                }
            }
        }
    }

    private func runShell(command: String, environment: [String: String]? = nil, completion: @escaping (Int32, String) -> Void) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        var env = ProcessInfo.processInfo.environment
        environment?.forEach { key, value in
            env[key] = value
        }
        process.environment = env
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { proc in
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            let output = (String(data: out, encoding: .utf8) ?? "") + (String(data: err, encoding: .utf8) ?? "")
            DispatchQueue.main.async {
                completion(proc.terminationStatus, output)
            }
        }
        do {
            try process.run()
        } catch {
            completion(1, "")
        }
    }

    @objc private func confirmAndUpdateModels() {
        let alert = NSAlert()
        alert.messageText = "Update models?"
        alert.informativeText = "This will download/update local models (small-q5_1, medium-q5_0, large-v3-turbo-q5_0). Continue?"
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            updateModels()
        }
    }

    @objc private func checkForUpdatesPressed() {
        checkForUpdates()
    }

    @objc private func resetUsageStats() {
        let alert = NSAlert()
        alert.messageText = "Сбросить статистику?"
        alert.informativeText = "Статистика диктовки за день/неделю/месяц и общий счетчик будут очищены."
        alert.addButton(withTitle: "Сбросить")
        alert.addButton(withTitle: "Отмена")
        alert.alertStyle = .warning
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else {
            return
        }

        resetUsageStatsData()
    }

    private func resetUsageStatsData() {
        usageStats = UsageStats()
        saveUsageStats()
        updateUsageStatsMenuState()
        showStatus("Статистика сброшена")
    }

    private func checkForUpdates(completion: ((SettingsSnapshot) -> Void)? = nil) {
        if updateCheckInProgress || modelUpdateInProgress {
            completion?(currentSettingsSnapshot())
            return
        }
        updateCheckInProgress = true
        beginActivity()
        checkUpdatesItem?.isEnabled = false
        modelUpdateItem?.isEnabled = false
        refreshSettingsWindow()
        showStatus("Проверка обновлений...")

        checkModelsStatus { [weak self] modelsFound, modelsTotal, versionsText, modelsUpdateAvailable in
            guard let self else { return }
            self.modelsStatusItem?.title = "Модели: \(modelsFound)/\(modelsTotal) установлены"
            self.modelsVersionItem?.title = "Версии моделей: \(versionsText)"
            self.modelsUpdateStateItem?.title = modelsUpdateAvailable ? "Обновление моделей: есть" : "Обновление моделей: нет"
            self.modelUpdateAvailable = modelsUpdateAvailable
            self.modelUpdateItem?.isEnabled = !self.modelUpdateInProgress && self.modelUpdateAvailable
            self.checkUpdatesItem?.isEnabled = true
            self.refreshSettingsWindow()
            self.updateCheckInProgress = false
            self.endActivity()
            self.showStatus("Проверка обновлений завершена")
            completion?(self.currentSettingsSnapshot())
        }
    }

    private func checkModelsStatus(completion: @escaping (Int, Int, String, Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let modelsDir = self.modelsDirectoryPath
            var found = 0
            var installedVersions: [String] = []
            var updateAvailable = false
            var localSHA: [String: String] = [:]
            for model in self.managedModels {
                let path = "\(modelsDir)/\(model)"
                if FileManager.default.fileExists(atPath: path) {
                    found += 1
                    installedVersions.append(model.replacingOccurrences(of: "ggml-", with: "").replacingOccurrences(of: ".bin", with: ""))
                    localSHA[model] = self.computeSHA256(path: path)
                } else {
                    updateAvailable = true
                }
            }

            if let remoteSHA = self.fetchRemoteModelSHA() {
                for model in self.managedModels {
                    guard let remote = remoteSHA[model] else {
                        continue
                    }
                    if let local = localSHA[model], !local.isEmpty {
                        if local != remote {
                            updateAvailable = true
                        }
                    } else {
                        updateAvailable = true
                    }
                }
            }

            let versionsText = installedVersions.isEmpty ? "нет" : installedVersions.joined(separator: ", ")
            DispatchQueue.main.async {
                completion(found, self.managedModels.count, versionsText, updateAvailable)
            }
        }
    }

    private func computeSHA256(path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", "shasum -a 256 \"\(path)\" | awk '{print $1}'"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func fetchRemoteModelSHA() -> [String: String]? {
        struct HFModelResponse: Decodable {
            struct Sibling: Decodable {
                struct LFS: Decodable {
                    let sha256: String?
                }
                let rfilename: String
                let lfs: LFS?
            }
            let siblings: [Sibling]
        }

        guard let url = URL(string: "https://huggingface.co/api/models/ggerganov/whisper.cpp") else {
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: [String: String]?
        let task = URLSession.shared.dataTask(with: url) { [managedModels] data, _, _ in
            defer { semaphore.signal() }
            guard let data else {
                return
            }
            guard let parsed = try? JSONDecoder().decode(HFModelResponse.self, from: data) else {
                return
            }
            var map: [String: String] = [:]
            for sibling in parsed.siblings where managedModels.contains(sibling.rfilename) {
                if let sha = sibling.lfs?.sha256?.lowercased() {
                    map[sibling.rfilename] = sha
                }
            }
            result = map
        }
        task.resume()

        let waitResult = semaphore.wait(timeout: .now() + 12.0)
        if waitResult == .timedOut {
            task.cancel()
            return nil
        }
        return result
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            HotkeyMode(rawValue: raw) != nil
        else {
            return
        }
        setHotkey(rawValue: raw)
    }

    private func setHotkey(rawValue: String) {
        guard let mode = HotkeyMode(rawValue: rawValue) else {
            return
        }
        hotkeyMode = mode
        saveHotkeyMode()
        updateHotkeyMenuState()
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title)")
    }

    @objc private func selectTranscribeModel(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            TranscribeModel(rawValue: raw) != nil
        else {
            return
        }
        setTranscribeModel(rawValue: raw)
    }

    private func setTranscribeModel(rawValue: String) {
        guard let model = TranscribeModel(rawValue: rawValue) else {
            return
        }
        transcribeModel = model
        saveTranscribeModel()
        updateTranscribeModelMenuState()
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title)")
    }

    @objc private func toggleLaunchAtLogin() {
        setLaunchAtLogin(!isLaunchAtLoginEnabled())
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #unavailable(macOS 13.0) {
            showStatus("Launch at Login unsupported on this macOS")
            UserDefaults.standard.set(false, forKey: launchAtLoginDefaultsKey)
            refreshSettingsWindow()
            return
        }

        do {
            let currentlyEnabled = isLaunchAtLoginEnabled()
            if currentlyEnabled && !enabled {
                try SMAppService.mainApp.unregister()
                showStatus("Launch at Login disabled")
            } else if !currentlyEnabled && enabled {
                try SMAppService.mainApp.register()
                showStatus("Launch at Login enabled")
            }
        } catch {
            showStatus("Launch at Login error")
        }
        updateLaunchAtLoginMenuState()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
