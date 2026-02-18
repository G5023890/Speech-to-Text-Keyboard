import AppKit
import ApplicationServices
import AVFoundation
import Foundation
import ServiceManagement

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

    var title: String {
        switch self {
        case .mediumQ5:
            return "medium-q5_0"
        case .smallQ5:
            return "small-q5_1"
        }
    }

    var fileName: String {
        switch self {
        case .mediumQ5:
            return "ggml-medium-q5_0.bin"
        case .smallQ5:
            return "ggml-small-q5_1.bin"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appSupportSubdir = "Voice Input"

    private var statusItem: NSStatusItem?
    private var menuBarIconImage: NSImage?
    private var loadingIndicator: NSProgressIndicator?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isRecording = false
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
    private let hotkeyDefaultsKey = "voice_input_hotkey_mode"
    private let transcribeModelDefaultsKey = "voice_input_transcribe_model"
    private var hotkeyMode: HotkeyMode = .shiftOption
    private var transcribeModel: TranscribeModel = .mediumQ5
    private var modelUpdateInProgress = false
    private var updateCheckInProgress = false
    private var modelUpdateAvailable = false
    private var activityCounter = 0
    private let managedModels = ["ggml-medium-q5_0.bin", "ggml-small-q5_1.bin"]
    private let legacyManagedModels = ["ggml-medium-q5_0.bin", "ggml-small-q5_1.bin", "ggml-medium.bin", "ggml-small.bin"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ensureModelsDirectoryReady()
        loadHotkeyMode()
        loadTranscribeModel()
        setupStatusItem()
        ensureAccessibilityPermission()
        ensureMicrophonePermission { _ in }
        setupHotkeyMonitors()
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title)")
    }

    private var modelsDirectoryPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportSubdir, isDirectory: true)
            .appendingPathComponent("models", isDirectory: true).path
    }

    private var legacyModelsDirectoryPath: String {
        return "\(NSHomeDirectory())/Documents/Develop/Voice input/models"
    }

    private var runtimeDirectoryPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(appSupportSubdir, isDirectory: true)
            .appendingPathComponent(".runtime", isDirectory: true).path
    }

    private var recordingPath: String {
        return "\(runtimeDirectoryPath)/ptt_input.wav"
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

        let menu = NSMenu()

        let settingsItem = NSMenuItem(title: "Настройки", action: nil, keyEquivalent: ",")
        let settingsMenu = NSMenu()
        settingsMenu.autoenablesItems = false

        let launchItem = NSMenuItem(title: "Запуск при входе", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        settingsMenu.addItem(launchItem)
        launchAtLoginItem = launchItem
        updateLaunchAtLoginMenuState()

        let hotkeyItem = NSMenuItem(title: "Горячая клавиша", action: nil, keyEquivalent: "")
        let hotkeySubmenu = NSMenu()
        hotkeySubmenu.autoenablesItems = false
        for mode in HotkeyMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectHotkey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.isEnabled = true
            hotkeySubmenu.addItem(item)
            hotkeyMenuItems[mode] = item
        }
        hotkeyItem.submenu = hotkeySubmenu
        settingsMenu.addItem(hotkeyItem)
        updateHotkeyMenuState()

        let transcribeModelItem = NSMenuItem(title: "Модель", action: nil, keyEquivalent: "")
        let transcribeModelSubmenu = NSMenu()
        transcribeModelSubmenu.autoenablesItems = false
        for model in TranscribeModel.allCases {
            let item = NSMenuItem(title: model.title, action: #selector(selectTranscribeModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.rawValue
            item.isEnabled = true
            transcribeModelSubmenu.addItem(item)
            transcribeModelMenuItems[model] = item
        }
        transcribeModelItem.submenu = transcribeModelSubmenu
        settingsMenu.addItem(transcribeModelItem)
        updateTranscribeModelMenuState()

        settingsMenu.addItem(NSMenuItem.separator())
        let checkItem = NSMenuItem(title: "Проверить обновления", action: #selector(checkForUpdatesPressed), keyEquivalent: "u")
        checkItem.target = self
        checkItem.isEnabled = true
        settingsMenu.addItem(checkItem)
        checkUpdatesItem = checkItem

        settingsMenu.addItem(NSMenuItem.separator())
        let mStatus = NSMenuItem(title: "Модели: не проверено", action: nil, keyEquivalent: "")
        mStatus.isEnabled = false
        settingsMenu.addItem(mStatus)
        modelsStatusItem = mStatus

        let mVersion = NSMenuItem(title: "Версии моделей: —", action: nil, keyEquivalent: "")
        mVersion.isEnabled = false
        settingsMenu.addItem(mVersion)
        modelsVersionItem = mVersion

        let mUpdateState = NSMenuItem(title: "Обновление моделей: —", action: nil, keyEquivalent: "")
        mUpdateState.isEnabled = false
        settingsMenu.addItem(mUpdateState)
        modelsUpdateStateItem = mUpdateState

        let mProgress = NSMenuItem(title: "Прогресс обновления: —", action: nil, keyEquivalent: "")
        mProgress.isEnabled = false
        mProgress.isHidden = true
        settingsMenu.addItem(mProgress)
        modelsProgressItem = mProgress

        let modelItem = NSMenuItem(title: "Обновить модели", action: #selector(confirmAndUpdateModels), keyEquivalent: "")
        modelItem.target = self
        modelItem.isEnabled = false
        settingsMenu.addItem(modelItem)
        modelUpdateItem = modelItem

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Voice Input", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
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

    private func updateHotkeyMenuState() {
        for (mode, item) in hotkeyMenuItems {
            item.state = (mode == hotkeyMode) ? .on : .off
        }
    }

    private func updateTranscribeModelMenuState() {
        for (model, item) in transcribeModelMenuItems {
            item.state = (model == transcribeModel) ? .on : .off
        }
    }

    private func updateLaunchAtLoginMenuState() {
        guard let launchAtLoginItem else {
            return
        }
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                launchAtLoginItem.state = .on
            case .requiresApproval:
                launchAtLoginItem.state = .mixed
            default:
                launchAtLoginItem.state = .off
            }
        } else {
            launchAtLoginItem.state = .off
            launchAtLoginItem.isEnabled = false
        }
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
                showStatus("Failed to start recording")
            }
        } catch {
            isRecording = false
            showStatus("Recorder error")
        }
    }

    private func stopRecordingAndPaste() {
        if !isRecording {
            return
        }
        isRecording = false
        recorder?.stop()
        recorder = nil
        showStatus("Transcribing...")

        runTranscribe(audioPath: recordingPath) { [weak self] exitCode, output, errorText in
            guard let self else { return }
            guard exitCode == 0 else {
                self.showStatus("STT error")
                self.showErrorAlert(title: "STT error", text: errorText.isEmpty ? "Transcription failed." : errorText)
                self.clearTransientData(clearClipboard: false)
                return
            }

            let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                self.showStatus("No speech detected")
                self.clearTransientData(clearClipboard: false)
                return
            }

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
        env["WHISPER_APP_SUPPORT_DIR"] = "\(NSHomeDirectory())/Library/Application Support/\(appSupportSubdir)"
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
        board.clearContents()
        board.setString(text, forType: .string)

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

    private func clearTransientData(clearClipboard: Bool) {
        let runtimeDir = runtimeDirectoryPath
        try? FileManager.default.removeItem(atPath: "\(runtimeDir)/ptt_input.txt")
        try? FileManager.default.removeItem(atPath: "\(runtimeDir)/ptt_input.wav")
        try? FileManager.default.removeItem(atPath: "\(runtimeDir)/recording.pid")
        if clearClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                NSPasteboard.general.clearContents()
            }
        }
    }

    private func showStatus(_ text: String) {
        if let button = statusItem?.button {
            button.toolTip = "Voice Input - \(text)"
        }
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
        } else {
            if let image = menuBarIconImage {
                button.title = ""
                button.image = image
                button.imagePosition = .imageOnly
            } else {
                button.image = nil
                button.title = "Mic"
            }
            loadingIndicator?.stopAnimation(nil)
        }
    }

    private func setModelProgress(_ percent: Int, detail: String) {
        modelsProgressItem?.isHidden = false
        modelsProgressItem?.title = "Прогресс обновления: \(percent)% (\(detail))"
    }

    private func clearModelProgress() {
        modelsProgressItem?.isHidden = true
        modelsProgressItem?.title = "Прогресс обновления: —"
    }

    private func showErrorAlert(title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func updateModels() {
        if modelUpdateInProgress {
            return
        }
        modelUpdateInProgress = true
        modelUpdateItem?.isEnabled = false
        beginActivity()
        setModelProgress(0, detail: "старт")
        showStatus("Updating models...")

        guard let scriptPath = transcribeScriptPath else {
            modelUpdateInProgress = false
            modelUpdateItem?.isEnabled = false
            clearModelProgress()
            endActivity()
            showStatus("Model update failed")
            showErrorAlert(title: "Model update failed", text: "Update script not found.")
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
                self.clearModelProgress()
                self.endActivity()
                self.showStatus("Model update failed")
                let alert = NSAlert()
                alert.messageText = "Model update failed"
                alert.informativeText = firstOutput.isEmpty ? "Check internet connection and try again." : firstOutput
                alert.alertStyle = .warning
                alert.runModal()
                self.checkForUpdates()
                return
            }
            self.setModelProgress(50, detail: "small-q5_1")

            let fastCommand = """
            "\(scriptPath)" download-fast-model
            """
            self.runShell(command: fastCommand, environment: scriptEnv) { [weak self] secondCode, secondOutput in
                guard let self else { return }
                self.modelUpdateInProgress = false
                self.endActivity()

                guard secondCode == 0 else {
                    self.modelUpdateItem?.isEnabled = false
                    self.clearModelProgress()
                    self.showStatus("Model update failed")
                    let alert = NSAlert()
                    alert.messageText = "Model update failed"
                    alert.informativeText = secondOutput.isEmpty ? "Check internet connection and try again." : secondOutput
                    alert.alertStyle = .warning
                    alert.runModal()
                    self.checkForUpdates()
                    return
                }

                self.setModelProgress(100, detail: "medium-q5_0")
                self.modelUpdateItem?.isEnabled = false
                self.showStatus("Models updated")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.clearModelProgress()
                    self?.checkForUpdates()
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
        alert.informativeText = "This will download/update local models (small-q5_1, medium-q5_0, medium). Continue?"
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

    private func checkForUpdates() {
        if updateCheckInProgress || modelUpdateInProgress {
            return
        }
        updateCheckInProgress = true
        beginActivity()
        checkUpdatesItem?.isEnabled = false
        modelUpdateItem?.isEnabled = false
        showStatus("Проверка обновлений...")

        checkModelsStatus { [weak self] modelsFound, modelsTotal, versionsText, modelsUpdateAvailable in
            guard let self else { return }
            self.modelsStatusItem?.title = "Модели: \(modelsFound)/\(modelsTotal) установлены"
            self.modelsVersionItem?.title = "Версии моделей: \(versionsText)"
            self.modelsUpdateStateItem?.title = modelsUpdateAvailable ? "Обновление моделей: есть" : "Обновление моделей: нет"
            self.modelUpdateAvailable = modelsUpdateAvailable
            self.modelUpdateItem?.isEnabled = !self.modelUpdateInProgress && self.modelUpdateAvailable
            self.checkUpdatesItem?.isEnabled = true
            self.updateCheckInProgress = false
            self.endActivity()
            self.showStatus("Проверка обновлений завершена")
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
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let parsed = try? JSONDecoder().decode(HFModelResponse.self, from: data) else {
            return nil
        }
        var map: [String: String] = [:]
        for sibling in parsed.siblings where managedModels.contains(sibling.rfilename) {
            if let sha = sibling.lfs?.sha256?.lowercased() {
                map[sibling.rfilename] = sha
            }
        }
        return map
    }

    @objc private func selectHotkey(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = HotkeyMode(rawValue: raw)
        else {
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
            let model = TranscribeModel(rawValue: raw)
        else {
            return
        }
        transcribeModel = model
        saveTranscribeModel()
        updateTranscribeModelMenuState()
        showStatus("PTT ready: \(hotkeyMode.title), model: \(transcribeModel.title)")
    }

    @objc private func toggleLaunchAtLogin() {
        if #unavailable(macOS 13.0) {
            showStatus("Launch at Login unsupported on this macOS")
            return
        }

        do {
            switch SMAppService.mainApp.status {
            case .enabled:
                try SMAppService.mainApp.unregister()
                showStatus("Launch at Login disabled")
            default:
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
