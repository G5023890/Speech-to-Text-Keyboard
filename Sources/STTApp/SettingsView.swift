import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                permissionPanel
                hotkeyPanel
                modelPanel
                runtimePanel
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            appState.refreshPermissions()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Local STT")
                        .font(.title2.bold())
                    Text(appState.statusMessage)
                        .font(.callout)
                        .foregroundStyle(statusTint)
                        .lineLimit(3)
                }
                Spacer()
                phaseBadge
            }
        }
        .panelStyle()
    }

    private var phaseBadge: some View {
        Text(phaseLabel)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassIfAvailable(tint: phaseTint)
    }

    private var permissionPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(.headline)
            PermissionRow(
                title: "Microphone",
                status: appState.microphonePermission.rawValue,
                isReady: appState.microphonePermission == .granted,
                actionTitle: "Request"
            ) {
                Task {
                    await PermissionService.requestMicrophoneAccess()
                    appState.refreshPermissions()
                }
            }
            PermissionRow(
                title: "Accessibility",
                status: appState.accessibilityTrusted ? "Granted" : "Required",
                isReady: appState.accessibilityTrusted,
                actionTitle: "Open"
            ) {
                PermissionService.requestAccessibilityAccess()
                appState.refreshPermissions()
            }
        }
        .panelStyle()
    }

    private var hotkeyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hotkeys")
                .font(.headline)
            ForEach(DictationProfile.allCases) { profile in
                HStack {
                    VStack(alignment: .leading) {
                        Text(profile.displayName)
                            .font(.body.weight(.medium))
                        Text("Hold \(profile.hotkeyDescription), speak, release to insert.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(profile.hotkeyDescription)
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .glassIfAvailable(tint: .blue.opacity(0.12))
                }
            }
        }
        .panelStyle()
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Models")
                .font(.headline)

            if let manager = appState.modelManager {
                Picker("Selected model", selection: Binding(
                    get: { manager.selectedModel },
                    set: { manager.select($0) }
                )) {
                    ForEach(WhisperModel.allCases) { model in
                        Text(model.displayName).tag(model)
                    }
                }

                ForEach(WhisperModel.allCases) { model in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.displayName)
                                Text(manager.isInstalled(model) ? "Installed" : model.filename)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                Task { try? await manager.download(model) }
                            } label: {
                                Label(manager.isInstalled(model) ? "Ready" : "Download", systemImage: manager.isInstalled(model) ? "checkmark.circle" : "arrow.down.circle")
                            }
                            .disabled(manager.downloadProgress != nil || manager.isInstalled(model))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Core ML Encoder")
                                Spacer()
                                Button {
                                    Task { try? await manager.downloadCoreMLEncoder(for: model) }
                                } label: {
                                    Label(manager.isCoreMLInstalled(model) ? "Installed" : "Download", systemImage: manager.isCoreMLInstalled(model) ? "bolt.badge.checkmark" : "bolt.badge.clock")
                                }
                                .disabled(manager.coreMLDownloadProgress != nil || manager.isCoreMLInstalled(model))
                            }
                            Text(manager.isCoreMLInstalled(model) ? model.coreMLEncoderDirectoryName : "Optional ANE acceleration")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let progress = manager.downloadProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        Text("Downloading \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let progress = manager.coreMLDownloadProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: progress)
                        Text("Downloading Core ML encoder \(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = manager.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("Model manager is starting.")
                    .foregroundStyle(.secondary)
            }
        }
        .panelStyle()
    }

    private var runtimePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime")
                .font(.headline)
            Toggle("Use VAD before transcription", isOn: $appState.useVAD)
            Text("VAD is experimental with the current whisper.cpp Metal build; if it fails, transcription retries without VAD.")
                .font(.caption)
                .foregroundStyle(.secondary)
            RuntimeRow(title: "Engine", value: "whisper.cpp CLI")
            RuntimeRow(title: "Acceleration", value: "Metal + optional Core ML encoder fallback")
            RuntimeRow(title: "Privacy", value: "No history, temporary audio deleted")
        }
        .panelStyle()
    }

    private var phaseLabel: String {
        switch appState.phase {
        case .idle: return "Idle"
        case .recording: return "Recording"
        case .transcribing: return "Transcribing"
        case .error: return "Error"
        }
    }

    private var phaseTint: Color {
        switch appState.phase {
        case .idle: return .green.opacity(0.16)
        case .recording: return .red.opacity(0.18)
        case .transcribing: return .blue.opacity(0.18)
        case .error: return .orange.opacity(0.18)
        }
    }

    private var statusTint: Color {
        if case .error = appState.phase {
            return .red
        }
        return .secondary
    }
}

private struct PermissionRow: View {
    let title: String
    let status: String
    let isReady: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(isReady ? .green : .orange)
            Text(title)
            Spacer()
            Text(status)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .disabled(isReady)
        }
    }
}

private struct RuntimeRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private extension View {
    func panelStyle() -> some View {
        modifier(PanelStyle())
    }

    @ViewBuilder
    func glassIfAvailable(tint: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.tint(tint).interactive(true), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            self
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct PanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .padding(16)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            content
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
