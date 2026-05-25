import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let appState = AppState()

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var hotkeyService: HotkeyService?
    private lazy var audioCapture = AudioCaptureService()
    private lazy var trainingAudioCapture = AudioCaptureService()
    private lazy var modelManager = ModelManager()
    private lazy var trainingStore = TrainingStore()
    private lazy var transcriptionEngine = WhisperCLITranscriptionEngine(modelManager: modelManager, trainingStore: trainingStore)
    private lazy var textInsertion = TextInsertionService()
    private var trainingReviewWindow: NSWindow?
    private var trainingCaptureProfile: DictationProfile?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        appState.modelManager = modelManager
        appState.trainingStore = trainingStore
        appState.refreshPermissions()

        hotkeyService = HotkeyService(
            onStart: { [weak self] profile in
                Task { @MainActor in
                    await self?.startRecording(profile: profile)
                }
            },
            onStop: { [weak self] profile in
                Task { @MainActor in
                    await self?.finishRecording(profile: profile)
                }
            },
            onTrainingToggle: { [weak self] in
                Task { @MainActor in
                    await self?.toggleTrainingCapture()
                }
            }
        )
        hotkeyService?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService?.stop()
        audioCapture.cancel()
        trainingAudioCapture.cancel()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Local STT")
        item.button?.target = self
        item.button?.action = #selector(toggleSettings)

        let menu = NSMenu()
        let openSettingsItem = NSMenuItem(title: "Open Settings", action: #selector(openSettings), keyEquivalent: ",")
        openSettingsItem.target = self
        menu.addItem(openSettingsItem)
        menu.addItem(.separator())
        let downloadSmallItem = NSMenuItem(title: "Download Small Model", action: #selector(downloadSmallModel), keyEquivalent: "")
        downloadSmallItem.target = self
        menu.addItem(downloadSmallItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
        appState.$phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.updateStatusIcon(phase)
            }
            .store(in: &appState.cancellables)
    }

    private func updateStatusIcon(_ phase: AppPhase) {
        let symbol: String
        switch phase {
        case .idle:
            symbol = "waveform"
        case .recording:
            symbol = "mic.fill"
        case .trainingRecording:
            symbol = "record.circle.fill"
        case .transcribing:
            symbol = "text.bubble.fill"
        case .error:
            symbol = "exclamationmark.triangle.fill"
        }
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Local STT")
    }

    @objc private func toggleSettings() {
        openSettings()
    }

    @objc private func openSettings() {
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            let hostingController = NSHostingController(
                rootView: SettingsView(appState: appState)
                    .frame(width: 560, height: 520)
            )
            window = NSWindow(contentViewController: hostingController)
            window.title = "Local STT Settings"
            window.setContentSize(NSSize(width: 560, height: 520))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func downloadSmallModel() {
        Task { await download(model: .small) }
    }

    private func download(model: WhisperModel) async {
        do {
            try await modelManager.download(model)
            appState.phase = .idle
            appState.statusMessage = "\(model.displayName) is ready"
        } catch {
            appState.phase = .error(error.localizedDescription)
            appState.statusMessage = error.localizedDescription
        }
    }

    private func startRecording(profile: DictationProfile) async {
        guard appState.phase.isReadyForRecording else { return }
        appState.refreshPermissions()

        guard appState.microphonePermission == .granted else {
            await PermissionService.requestMicrophoneAccess()
            appState.refreshPermissions()
            return
        }

        guard appState.accessibilityTrusted else {
            PermissionService.requestAccessibilityAccess()
            appState.refreshPermissions()
            return
        }

        do {
            appState.activeProfile = profile
            appState.phase = .recording(profile)
            appState.statusMessage = "Recording \(profile.displayName)"
            try audioCapture.start()
        } catch {
            appState.phase = .error(error.localizedDescription)
            appState.statusMessage = error.localizedDescription
        }
    }

    private func finishRecording(profile: DictationProfile) async {
        guard case .recording = appState.phase else { return }
        appState.phase = .transcribing(profile)
        appState.statusMessage = "Transcribing \(profile.displayName)"

        do {
            let audioURL = try audioCapture.stop()
            defer { try? FileManager.default.removeItem(at: audioURL) }

            let result = try await transcriptionEngine.transcribe(
                audioURL: audioURL,
                profile: profile,
                useVAD: appState.useVAD
            )

            if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                appState.statusMessage = "No speech detected"
            } else {
                try textInsertion.insert(result)
                appState.statusMessage = "Inserted \(result.count) characters"
            }
            appState.phase = .idle
        } catch {
            appState.phase = .error(error.localizedDescription)
            appState.statusMessage = error.localizedDescription
        }
    }

    private func toggleTrainingCapture() async {
        switch appState.phase {
        case .trainingRecording(let profile):
            await finishTrainingRecording(profile: profile)
        case .idle, .error:
            await startTrainingRecording(profile: appState.trainingProfile)
        default:
            break
        }
    }

    private func startTrainingRecording(profile: DictationProfile) async {
        appState.refreshPermissions()

        guard appState.microphonePermission == .granted else {
            await PermissionService.requestMicrophoneAccess()
            appState.refreshPermissions()
            return
        }

        do {
            trainingCaptureProfile = profile
            appState.phase = .trainingRecording(profile)
            appState.statusMessage = "Training capture \(profile.displayName)"
            try trainingAudioCapture.start()
        } catch {
            appState.phase = .error(error.localizedDescription)
            appState.statusMessage = error.localizedDescription
        }
    }

    private func finishTrainingRecording(profile: DictationProfile) async {
        appState.phase = .transcribing(profile)
        appState.statusMessage = "Preparing training example"

        do {
            let audioURL = try trainingAudioCapture.stop()
            let transcript = try await transcriptionEngine.transcribe(
                audioURL: audioURL,
                profile: profile,
                useVAD: false
            )
            openTrainingReview(audioURL: audioURL, profile: profile, initialTranscript: transcript)
            appState.phase = .idle
            appState.statusMessage = "Review training example"
        } catch {
            appState.phase = .error(error.localizedDescription)
            appState.statusMessage = error.localizedDescription
        }
    }

    private func openTrainingReview(audioURL: URL, profile: DictationProfile, initialTranscript: String) {
        let view = TrainingReviewView(
            profile: profile,
            initialTranscript: initialTranscript,
            onSave: { [weak self] transcript in
                Task { @MainActor in
                    self?.saveTrainingExample(audioURL: audioURL, transcript: transcript, profile: profile)
                }
            },
            onCancel: { [weak self] in
                Task { @MainActor in
                    try? FileManager.default.removeItem(at: audioURL)
                    self?.trainingReviewWindow?.close()
                    self?.trainingReviewWindow = nil
                    self?.appState.statusMessage = "Training example discarded"
                }
            }
        )

        let window = NSWindow(contentViewController: NSHostingController(rootView: view.frame(width: 560, height: 360)))
        window.title = "Review Training Example"
        window.setContentSize(NSSize(width: 560, height: 360))
        window.styleMask = [.titled, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        trainingReviewWindow = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func saveTrainingExample(audioURL: URL, transcript: String, profile: DictationProfile) {
        do {
            try trainingStore.saveExample(
                audioURL: audioURL,
                transcript: transcript,
                profile: profile,
                modelName: trainingStore.selectedTrainedModel?.displayName ?? modelManager.selectedModel.displayName
            )
            trainingReviewWindow?.close()
            trainingReviewWindow = nil
            appState.statusMessage = "Training example saved"
        } catch {
            appState.phase = .error(error.localizedDescription)
            appState.statusMessage = error.localizedDescription
        }
    }
}
