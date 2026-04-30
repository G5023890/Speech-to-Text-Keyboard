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
    private lazy var modelManager = ModelManager()
    private lazy var transcriptionEngine = WhisperCLITranscriptionEngine(modelManager: modelManager)
    private lazy var textInsertion = TextInsertionService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        appState.modelManager = modelManager
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
            }
        )
        hotkeyService?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyService?.stop()
        audioCapture.cancel()
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
        let downloadMediumItem = NSMenuItem(title: "Download Medium Model", action: #selector(downloadMediumModel), keyEquivalent: "")
        downloadMediumItem.target = self
        menu.addItem(downloadMediumItem)
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

    @objc private func downloadMediumModel() {
        Task { await download(model: .medium) }
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
}
