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
    case largeV3TurboQ4KM = "ggml-large-v3-turbo-q4_K_M"
    case mediumQ5 = "ggml-medium-q5_0"
    case smallQ8 = "ggml-small-q8_0"
    case smallQ5 = "ggml-small-q5_1"
    case mediumQ4 = "ggml-medium-q4_0"
    case legacyLargeV3TurboQ5 = "largeV3TurboQ5"

    var title: String {
        switch self {
        case .largeV3TurboQ4KM:
            return "large-v3-turbo-q4_K_M"
        case .mediumQ5:
            return "medium-q5_0"
        case .smallQ8:
            return "small-q8_0"
        case .smallQ5:
            return "small-q5_1"
        case .mediumQ4:
            return "medium-q4_0"
        case .legacyLargeV3TurboQ5:
            return "large-v3-turbo-q5_0"
        }
    }

    var fileName: String {
        switch self {
        case .largeV3TurboQ4KM:
            return "ggml-large-v3-turbo-q4_K_M.bin"
        case .mediumQ5:
            return "ggml-medium-q5_0.bin"
        case .smallQ8:
            return "ggml-small-q8_0.bin"
        case .smallQ5:
            return "ggml-small-q5_1.bin"
        case .mediumQ4:
            return "ggml-medium-q4_0.bin"
        case .legacyLargeV3TurboQ5:
            return "ggml-large-v3-turbo-q5_0.bin"
        }
    }

    static func fromPersisted(_ rawValue: String) -> TranscribeModel? {
        if let direct = TranscribeModel(rawValue: rawValue) {
            return direct
        }
        switch rawValue {
        case "mediumQ5":
            return .mediumQ5
        case "smallQ5":
            return .smallQ5
        case "largeV3TurboQ5":
            return .legacyLargeV3TurboQ5
        default:
            return nil
        }
    }
}

final class SettingsWindow: NSWindow {
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()

        if event.keyCode == 53 {
            performClose(nil)
            return
        }
        if modifiers.contains(.command), key == "w" {
            performClose(nil)
            return
        }

        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
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
        var words: Int = 0

        init() {}

        private enum CodingKeys: String, CodingKey {
            case sessions
            case seconds
            case characters
            case words
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sessions = try container.decodeIfPresent(Int.self, forKey: .sessions) ?? 0
            seconds = try container.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
            characters = try container.decodeIfPresent(Int.self, forKey: .characters) ?? 0
            words = try container.decodeIfPresent(Int.self, forKey: .words) ?? 0
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(sessions, forKey: .sessions)
            try container.encode(seconds, forKey: .seconds)
            try container.encode(characters, forKey: .characters)
            try container.encode(words, forKey: .words)
        }
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
    private let audioManager = AudioManager()
    private var partialLoopTask: Task<Void, Never>?
    private var partialInferenceInFlight = false
    private var lastPartialDraft: String = ""
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
    private let languageModeDefaultsKey = "voice_input_language_mode"
    private let launchAtLoginDefaultsKey = "voice_input_launch_at_login"
    private var hotkeyMode: HotkeyMode = .shiftOption
    private var transcribeModel: TranscribeModel = .mediumQ5
    private var languageMode: LanguageMode = .auto
    private var modelUpdateInProgress = false
    private var updateCheckInProgress = false
    private var modelUpdateAvailable = false
    private var modelManagementInProgress = false
    private var modelManagementStatus = "Готово"
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
        loadLanguageMode()
        setupStatusItem()
        ensureAccessibilityPermission()
        ensureMicrophonePermission { _ in }
        setupHotkeyMonitors()
        Task { [weak self] in
            guard let self else { return }
            let modelPath = "\(self.modelsDirectoryPath)/\(self.transcribeModel.fileName)"
            try? await SpeechEngine.shared.warmup(modelPath: modelPath)
        }
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title)")
    }

    private var appSupportDirectoryPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportSubdir, isDirectory: true).path
    }

    private var modelsDirectoryPath: String {
        return "\(appSupportDirectoryPath)/Models"
    }

    private var legacyLowercaseModelsDirectoryPath: String {
        return "\(appSupportDirectoryPath)/models"
    }

    private var downloadsDirectoryPath: String {
        return "\(appSupportDirectoryPath)/Downloads"
    }

    private var catalogDirectoryPath: String {
        return "\(appSupportDirectoryPath)/Catalog"
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

    private var runtimeDiagnosticsPath: String {
        return "\(appSupportDirectoryPath)/runtime_diagnostics.log"
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
        try? fileManager.createDirectory(atPath: downloadsDirectoryPath, withIntermediateDirectories: true)
        try? fileManager.createDirectory(atPath: catalogDirectoryPath, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: legacyLowercaseModelsDirectoryPath),
           let files = try? fileManager.contentsOfDirectory(atPath: legacyLowercaseModelsDirectoryPath)
        {
            for file in files where file.hasSuffix(".bin") {
                let oldPath = "\(legacyLowercaseModelsDirectoryPath)/\(file)"
                let newPath = "\(modelsDirectoryPath)/\(file)"
                if !fileManager.fileExists(atPath: newPath) {
                    try? fileManager.copyItem(atPath: oldPath, toPath: newPath)
                }
            }
        }

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
        partialLoopTask?.cancel()
        partialLoopTask = nil
        audioManager.stop()
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
        let window = SettingsWindow(contentViewController: hostingController)
        window.setContentSize(NSSize(width: 920, height: 700))
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
            setLanguageMode: { [weak self] rawValue in
                self?.setLanguageMode(rawValue: rawValue)
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
            addModelFromURL: { [weak self] url, completion in
                guard let self else {
                    completion(.mock)
                    return
                }
                self.addModelFromURL(url, completion: completion)
            },
            deleteModel: { [weak self] fileName, completion in
                guard let self else {
                    completion(.mock)
                    return
                }
                self.deleteInstalledModel(fileName, completion: completion)
            },
            openModelsFolder: { [weak self] in
                self?.openModelsFolder()
            },
            resetStats: { [weak self] in
                self?.resetUsageStatsData()
            }
        )
    }

    private func installedModelsCount() -> Int {
        return installedModels().count
    }

    private func installedModels() -> [SettingsInstalledModel] {
        let fileManager = FileManager.default
        let files = (try? fileManager.contentsOfDirectory(atPath: modelsDirectoryPath))?
            .filter { $0.hasSuffix(".bin") }
            .sorted() ?? []

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true

        return files.map { file in
            let fullPath = "\(modelsDirectoryPath)/\(file)"
            let attributes = try? fileManager.attributesOfItem(atPath: fullPath)
            let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let sizeText = bytes > 0 ? formatter.string(fromByteCount: bytes) : "—"
            let normalized = file
                .replacingOccurrences(of: "ggml-", with: "")
                .replacingOccurrences(of: ".bin", with: "")
            let displayName = TranscribeModel.allCases.first(where: { $0.fileName == file })?.title ?? normalized

            return SettingsInstalledModel(
                id: file,
                fileName: file,
                displayName: displayName,
                sizeText: sizeText,
                isManaged: managedModels.contains(file),
                isActive: file == transcribeModel.fileName
            )
        }
    }

    private func currentSettingsSnapshot() -> SettingsSnapshot {
        let today = usageForLastDays(1)
        let week = usageForCurrentWeek()
        let month = usageForCurrentMonth()
        let weekHasAggregate = week.sessions > today.sessions || week.words > today.words || week.seconds > today.seconds + 0.001
        let monthHasAggregate = month.sessions > today.sessions || month.words > today.words || month.seconds > today.seconds + 0.001
        let totalHasAggregate = usageStats.total.sessions > today.sessions || usageStats.total.words > today.words || usageStats.total.seconds > today.seconds + 0.001
        let stats = SettingsStats(
            todaySeconds: today.seconds,
            weekSeconds: week.seconds,
            monthSeconds: month.seconds,
            totalSeconds: usageStats.total.seconds,
            todayWords: today.words,
            weekWords: week.words,
            monthWords: month.words,
            sessions: usageStats.total.sessions,
            words: usageStats.total.words,
            hasWeeklyAggregate: weekHasAggregate,
            hasMonthlyAggregate: monthHasAggregate,
            hasTotalAggregate: totalHasAggregate
        )
        return SettingsSnapshot(
            launchAtLoginEnabled: isLaunchAtLoginEnabled(),
            selectedHotkey: hotkeyMode.rawValue,
            selectedModelID: transcribeModel.rawValue,
            selectedLanguageMode: languageMode.rawValue,
            installedModelCount: installedModelsCount(),
            totalModelCount: managedModels.count,
            updatesAvailable: modelUpdateAvailable,
            lastCheckStatus: settingsLastCheckStatusText(),
            stats: stats,
            isCheckingUpdates: updateCheckInProgress,
            isUpdatingModels: modelUpdateInProgress,
            installedModels: installedModels(),
            modelManagementStatus: modelManagementStatus,
            isManagingModels: modelManagementInProgress
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

    private func sanitizedModelFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.replacingOccurrences(of: " ", with: "_")
        let filtered = normalized.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" || scalar == "." {
                return Character(scalar)
            }
            return "_"
        }
        let collapsed = String(filtered).replacingOccurrences(of: "__", with: "_")
        if collapsed.isEmpty {
            return "model-\(UUID().uuidString.prefix(8)).bin"
        }
        return collapsed.hasSuffix(".bin") ? collapsed : "\(collapsed).bin"
    }

    private func addModelFromURL(_ urlString: String, completion: ((SettingsSnapshot) -> Void)? = nil) {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            modelManagementStatus = "Укажите URL модели"
            refreshSettingsWindow()
            completion?(currentSettingsSnapshot())
            return
        }
        guard let remoteURL = URL(string: trimmed),
              let scheme = remoteURL.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else {
            modelManagementStatus = "Некорректный URL"
            refreshSettingsWindow()
            completion?(currentSettingsSnapshot())
            return
        }

        let sourceName = remoteURL.lastPathComponent.isEmpty ? "model" : remoteURL.lastPathComponent
        let fileName = sanitizedModelFileName(sourceName)
        let destinationURL = URL(fileURLWithPath: "\(modelsDirectoryPath)/\(fileName)")
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            modelManagementStatus = "Модель уже установлена: \(fileName)"
            refreshSettingsWindow()
            completion?(currentSettingsSnapshot())
            return
        }

        try? FileManager.default.createDirectory(atPath: modelsDirectoryPath, withIntermediateDirectories: true)
        modelManagementInProgress = true
        modelManagementStatus = "Загрузка \(fileName)…"
        refreshSettingsWindow()
        beginActivity()

        let request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 1200)
        let task = URLSession.shared.downloadTask(with: request) { [weak self] tempURL, response, error in
            DispatchQueue.main.async {
                guard let self else { return }
                defer {
                    self.modelManagementInProgress = false
                    self.endActivity()
                    self.refreshSettingsWindow()
                    completion?(self.currentSettingsSnapshot())
                }

                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    self.modelManagementStatus = "Ошибка загрузки: HTTP \(http.statusCode)"
                    return
                }
                guard let tempURL else {
                    self.modelManagementStatus = "Не удалось загрузить модель"
                    if let error {
                        self.showStatus("Model download error: \(error.localizedDescription)")
                    }
                    return
                }

                do {
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    self.modelManagementStatus = "Модель добавлена: \(fileName)"
                    self.showStatus("Model added: \(fileName)")
                } catch {
                    self.modelManagementStatus = "Не удалось сохранить модель"
                    self.showStatus("Model save failed")
                }
            }
        }
        task.resume()
    }

    private func deleteInstalledModel(_ fileName: String, completion: ((SettingsSnapshot) -> Void)? = nil) {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            modelManagementStatus = "Выберите модель для удаления"
            refreshSettingsWindow()
            completion?(currentSettingsSnapshot())
            return
        }
        if trimmed == transcribeModel.fileName {
            modelManagementStatus = "Нельзя удалить активную модель"
            refreshSettingsWindow()
            completion?(currentSettingsSnapshot())
            return
        }

        let targetPath = "\(modelsDirectoryPath)/\(trimmed)"
        guard FileManager.default.fileExists(atPath: targetPath) else {
            modelManagementStatus = "Модель не найдена"
            refreshSettingsWindow()
            completion?(currentSettingsSnapshot())
            return
        }

        modelManagementInProgress = true
        refreshSettingsWindow()
        do {
            try FileManager.default.removeItem(atPath: targetPath)
            if managedModels.contains(trimmed) {
                modelUpdateAvailable = true
            }
            modelManagementStatus = "Модель удалена: \(trimmed)"
            showStatus("Model removed: \(trimmed)")
        } catch {
            modelManagementStatus = "Не удалось удалить модель"
            showStatus("Model remove failed")
        }
        modelManagementInProgress = false
        refreshSettingsWindow()
        completion?(currentSettingsSnapshot())
    }

    private func openModelsFolder() {
        try? FileManager.default.createDirectory(atPath: modelsDirectoryPath, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: modelsDirectoryPath, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        modelManagementStatus = "Открыта папка моделей"
        refreshSettingsWindow()
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
        transcribeModel = TranscribeModel.fromPersisted(saved) ?? .mediumQ5
    }

    private func saveTranscribeModel() {
        UserDefaults.standard.set(transcribeModel.rawValue, forKey: transcribeModelDefaultsKey)
    }

    private func loadLanguageMode() {
        let saved = UserDefaults.standard.string(forKey: languageModeDefaultsKey) ?? LanguageMode.auto.rawValue
        languageMode = LanguageMode(rawValue: saved) ?? .auto
    }

    private func saveLanguageMode() {
        UserDefaults.standard.set(languageMode.rawValue, forKey: languageModeDefaultsKey)
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
                bucket.words += value.words
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
                bucket.words += value.words
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
                bucket.words += value.words
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
        let words = countWords(text)
        guard seconds > 0 || chars > 0 || words > 0 else {
            return
        }

        let key = dayKey(for: Date())
        var day = usageStats.daily[key] ?? UsageBucket()
        day.sessions += 1
        day.seconds += seconds
        day.characters += chars
        day.words += words
        usageStats.daily[key] = day

        usageStats.total.sessions += 1
        usageStats.total.seconds += seconds
        usageStats.total.characters += chars
        usageStats.total.words += words

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

    private func appendRuntimeDiagnostic(_ message: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: appSupportDirectoryPath, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp)\t\(message)\n"
        if !fileManager.fileExists(atPath: runtimeDiagnosticsPath) {
            try? line.write(to: URL(fileURLWithPath: runtimeDiagnosticsPath), atomically: true, encoding: .utf8)
            return
        }
        if let handle = FileHandle(forWritingAtPath: runtimeDiagnosticsPath) {
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
        appendRuntimeDiagnostic("ptt_begin_requested model=\(transcribeModel.fileName) lang=\(languageMode.rawValue)")
        isRecording = true
        recordingStartedAt = Date()
        lastPartialDraft = ""
        partialInferenceInFlight = false
        startRecordingHalo()
        showStatus("Recording...")
        do {
            try audioManager.start()
            appendRuntimeDiagnostic("audio_engine_started")
            startPartialLoop()
        } catch {
            appendRuntimeDiagnostic("audio_engine_start_failed error=\(error.localizedDescription)")
            isRecording = false
            recordingStartedAt = nil
            stopRecordingHalo()
            showStatus("Audio engine error")
        }
    }

    private func stopRecordingAndPaste() {
        if !isRecording {
            return
        }
        appendRuntimeDiagnostic("ptt_stop_requested")
        isRecording = false
        stopRecordingHalo()
        partialLoopTask?.cancel()
        partialLoopTask = nil
        let sessionDuration = max(0.0, Date().timeIntervalSince(recordingStartedAt ?? Date()))
        audioManager.stop()
        recordingStartedAt = nil
        appendRuntimeDiagnostic("audio_engine_stopped duration=\(String(format: "%.2f", sessionDuration))")

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
        let finalSamples = audioManager.snapshotSpeechSamples()
        appendRuntimeDiagnostic("final_samples_count=\(finalSamples.count)")
        if finalSamples.count < 320 {
            appendTranscriptionDiagnostic(
                status: "rejected",
                durationSeconds: sessionDuration,
                text: "",
                reason: "empty_audio_after_vad"
            )
            showStatus("No speech detected")
            clearTransientData(clearClipboard: false)
            return
        }
        let modelPath = "\(modelsDirectoryPath)/\(transcribeModel.fileName)"
        Task { [weak self] in
            guard let self else { return }
            do {
                self.appendRuntimeDiagnostic("final_decode_started model_path=\(modelPath)")
                let output = try await SpeechEngine.shared.transcribe(
                    samples: finalSamples,
                    modelPath: modelPath,
                    languageMode: self.languageMode,
                    pass: .final
                )
                var finalText = output.text
                var finalLanguage = output.detectedLanguageCode
                var finalConfidence = output.confidence
                if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.appendRuntimeDiagnostic("native_empty_try_cli_fallback")
                    do {
                        let fallbackText = try await self.transcribeViaScriptFallback(
                            samples: finalSamples,
                            modelPath: modelPath,
                            languageMode: self.languageMode
                        )
                        let fallbackTrimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
                        self.appendRuntimeDiagnostic("cli_fallback_done text_len=\(fallbackTrimmed.count)")
                        if !fallbackTrimmed.isEmpty {
                            finalText = fallbackTrimmed
                            finalLanguage = self.languageMode.whisperLanguageCode ?? output.detectedLanguageCode
                            finalConfidence = max(0.55, output.confidence)
                        }
                    } catch {
                        self.appendRuntimeDiagnostic("cli_fallback_failed error=\(error.localizedDescription)")
                    }
                }
                let finalizedText = finalText
                let finalizedLanguage = finalLanguage
                let finalizedConfidence = finalConfidence
                await MainActor.run {
                    self.appendRuntimeDiagnostic("final_decode_done text_len=\(finalizedText.count) conf=\(String(format: "%.2f", finalizedConfidence)) lang=\(finalizedLanguage ?? "nil")")
                    self.handleFinalTranscription(
                        text: finalizedText,
                        duration: sessionDuration,
                        detectedLanguageCode: finalizedLanguage,
                        confidence: finalizedConfidence
                    )
                }
            } catch {
                await MainActor.run {
                    self.appendRuntimeDiagnostic("final_decode_failed error=\(error.localizedDescription)")
                    self.appendTranscriptionDiagnostic(
                        status: "rejected",
                        durationSeconds: sessionDuration,
                        text: "",
                        reason: "stt_error_native"
                    )
                    self.showStatus("STT error")
                    self.showErrorAlert(title: "STT error", text: error.localizedDescription)
                    self.clearTransientData(clearClipboard: false)
                }
            }
        }
    }

    private func startPartialLoop() {
        partialLoopTask?.cancel()
        let modelPath = "\(modelsDirectoryPath)/\(transcribeModel.fileName)"
        partialLoopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                if !self.isRecording { return }
                if self.partialInferenceInFlight { continue }
                self.partialInferenceInFlight = true
                let samples = self.audioManager.snapshotSpeechSamples()
                if samples.count < 1600 {
                    self.appendRuntimeDiagnostic("partial_skip_small_buffer samples=\(samples.count)")
                    self.partialInferenceInFlight = false
                    continue
                }
                do {
                    let output = try await SpeechEngine.shared.transcribe(
                        samples: samples,
                        modelPath: modelPath,
                        languageMode: self.languageMode,
                        pass: .partial
                    )
                    await MainActor.run {
                        self.lastPartialDraft = output.text
                        self.appendRuntimeDiagnostic("partial_decode_done text_len=\(output.text.count) conf=\(String(format: "%.2f", output.confidence))")
                        let draft = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !draft.isEmpty {
                            let short = draft.count > 80 ? "\(draft.prefix(80))…" : draft
                            self.showStatus("Черновик: \(short)")
                        }
                    }
                } catch {
                    self.appendRuntimeDiagnostic("partial_decode_failed error=\(error.localizedDescription)")
                }
                self.partialInferenceInFlight = false
            }
        }
    }

    private func handleFinalTranscription(text: String, duration: Double, detectedLanguageCode: String?, confidence: Float) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        appendRuntimeDiagnostic("handle_final text_len=\(trimmedText.count)")
        guard !trimmedText.isEmpty else {
            appendTranscriptionDiagnostic(
                status: "rejected",
                durationSeconds: duration,
                text: "",
                reason: "empty_output"
            )
            showStatus("No speech detected")
            clearTransientData(clearClipboard: false)
            return
        }

        let decision = shouldRejectTranscript(trimmedText, durationSeconds: duration)
        if decision.reject {
            appendTranscriptionDiagnostic(
                status: "rejected",
                durationSeconds: duration,
                text: trimmedText,
                reason: decision.reason
            )
            showStatus("Артефакт распознавания (пропущено)")
            clearTransientData(clearClipboard: false)
            return
        }

        lastAcceptedTranscript = trimmedText
        let languagePart = detectedLanguageCode.map { "lang=\($0)" } ?? "lang=auto"
        appendTranscriptionDiagnostic(
            status: "accepted",
            durationSeconds: duration,
            text: trimmedText,
            reason: "\(languagePart),conf=\(String(format: "%.2f", confidence))"
        )
        recordUsage(durationSeconds: duration, text: trimmedText)

        let pasted = pasteText(trimmedText)
        if pasted {
            showStatus("Pasted")
            clearTransientData(clearClipboard: true)
        } else {
            showStatus("Paste blocked, text copied")
            clearTransientData(clearClipboard: false)
            showErrorAlert(title: "Auto-paste blocked", text: "Text is copied to clipboard. Grant Accessibility for Voice Input to allow auto-paste.")
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

    private func runShellAsync(command: String, environment: [String: String]? = nil) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            runShell(command: command, environment: environment) { code, output in
                continuation.resume(returning: (code, output))
            }
        }
    }

    private func transcribeViaScriptFallback(samples: [Float], modelPath: String, languageMode: LanguageMode) async throws -> String {
        guard let scriptPath = transcribeScriptPath else {
            throw NSError(domain: "VoiceInput", code: 3101, userInfo: [NSLocalizedDescriptionKey: "Fallback script not found"])
        }
        guard !samples.isEmpty else {
            return ""
        }

        try FileManager.default.createDirectory(atPath: runtimeDirectoryPath, withIntermediateDirectories: true)
        let wavPath = recordingPath
        try writeSamplesAsWav(samples, to: wavPath)

        let env: [String: String] = [
            "WHISPER_MODEL": modelPath,
            "WHISPER_MODEL_DIR": modelsDirectoryPath,
            "WHISPER_APP_SUPPORT_DIR": appSupportDirectoryPath,
            "WHISPER_RUNTIME_DIR": runtimeDirectoryPath,
            "WHISPER_LANGUAGE": languageMode.whisperLanguageCode ?? "auto",
            "WHISPER_THREADS": "\(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))",
            "WHISPER_BEAM_SIZE": "1",
            "WHISPER_BEST_OF": "1",
            "WHISPER_GPU_FALLBACK": "1"
        ]
        let command = "\(shellQuote(scriptPath)) transcribe \(shellQuote(wavPath))"
        let (code, output) = await runShellAsync(command: command, environment: env)
        if code != 0 {
            throw NSError(domain: "VoiceInput", code: 3102, userInfo: [NSLocalizedDescriptionKey: output.isEmpty ? "Fallback transcription failed" : output])
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeSamplesAsWav(_ samples: [Float], to path: String) throws {
        let sampleRate: UInt32 = 16_000
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let blockAlign: UInt16 = channels * (bitsPerSample / 8)
        let byteRate: UInt32 = sampleRate * UInt32(blockAlign)

        var pcm = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = Int16(clamped * Float(Int16.max))
            var le = scaled.littleEndian
            withUnsafeBytes(of: &le) { pcm.append(contentsOf: $0) }
        }

        let dataChunkSize = UInt32(pcm.count)
        let riffChunkSize = 36 + dataChunkSize

        var wav = Data()
        wav.append(Data("RIFF".utf8))
        appendLE(riffChunkSize, to: &wav)
        wav.append(Data("WAVE".utf8))
        wav.append(Data("fmt ".utf8))
        appendLE(UInt32(16), to: &wav) // PCM fmt chunk size
        appendLE(UInt16(1), to: &wav) // PCM format
        appendLE(channels, to: &wav)
        appendLE(sampleRate, to: &wav)
        appendLE(byteRate, to: &wav)
        appendLE(blockAlign, to: &wav)
        appendLE(bitsPerSample, to: &wav)
        wav.append(Data("data".utf8))
        appendLE(dataChunkSize, to: &wav)
        wav.append(pcm)

        try wav.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
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
            TranscribeModel.fromPersisted(raw) != nil
        else {
            return
        }
        setTranscribeModel(rawValue: raw)
    }

    private func setTranscribeModel(rawValue: String) {
        guard let model = TranscribeModel.fromPersisted(rawValue) else {
            return
        }
        transcribeModel = model
        saveTranscribeModel()
        updateTranscribeModelMenuState()
        let modelPath = "\(modelsDirectoryPath)/\(transcribeModel.fileName)"
        Task {
            try? await SpeechEngine.shared.warmup(modelPath: modelPath)
        }
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title)")
    }

    private func setLanguageMode(rawValue: String) {
        guard let mode = LanguageMode(rawValue: rawValue) else {
            return
        }
        languageMode = mode
        saveLanguageMode()
        refreshSettingsWindow()
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title), lang: \(mode.title)")
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
