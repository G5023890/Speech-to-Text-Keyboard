import Foundation
import SwiftUI

struct ModelOption: Identifiable, Hashable {
    let id: String
    let title: String
    let isRecommended: Bool
}

struct SettingsInstalledModel: Identifiable, Hashable {
    let id: String
    let fileName: String
    let displayName: String
    let sizeText: String
    let isManaged: Bool
    let isActive: Bool
}

struct SettingsStats: Equatable {
    var todaySeconds: Double
    var weekSeconds: Double
    var monthSeconds: Double
    var totalSeconds: Double
    var todayWords: Int
    var weekWords: Int
    var monthWords: Int
    var sessions: Int
    var words: Int
    var hasWeeklyAggregate: Bool
    var hasMonthlyAggregate: Bool
    var hasTotalAggregate: Bool

    static let mock = SettingsStats(
        todaySeconds: 118,
        weekSeconds: 724,
        monthSeconds: 2592,
        totalSeconds: 8040,
        todayWords: 42,
        weekWords: 187,
        monthWords: 311,
        sessions: 18,
        words: 311,
        hasWeeklyAggregate: true,
        hasMonthlyAggregate: true,
        hasTotalAggregate: true
    )
}

struct SettingsSnapshot: Equatable {
    var launchAtLoginEnabled: Bool
    var showsMenuBarIcon: Bool
    var selectedHotkey: String
    var selectedModelID: String
    var selectedLanguageMode: String
    var installedModelCount: Int
    var totalModelCount: Int
    var updatesAvailable: Bool
    var lastCheckStatus: String
    var stats: SettingsStats
    var isCheckingUpdates: Bool
    var isUpdatingModels: Bool
    var installedModels: [SettingsInstalledModel]
    var modelManagementStatus: String
    var isManagingModels: Bool

    static let mock = SettingsSnapshot(
        launchAtLoginEnabled: true,
        showsMenuBarIcon: true,
        selectedHotkey: HotkeyMode.shiftOption.rawValue,
        selectedModelID: TranscribeModel.mediumQ5.rawValue,
        selectedLanguageMode: LanguageMode.auto.rawValue,
        installedModelCount: 3,
        totalModelCount: 3,
        updatesAvailable: false,
        lastCheckStatus: "Обновлений нет",
        stats: .mock,
        isCheckingUpdates: false,
        isUpdatingModels: false,
        installedModels: [],
        modelManagementStatus: "Готово",
        isManagingModels: false
    )
}

struct SettingsActions {
    var snapshot: () -> SettingsSnapshot
    var setLaunchAtLogin: (Bool) -> Void
    var setShowsMenuBarIcon: (Bool) -> Void
    var setHotkey: (String) -> Void
    var setModel: (String) -> Void
    var setLanguageMode: (String) -> Void
    var checkUpdates: (@escaping (SettingsSnapshot) -> Void) -> Void
    var updateModels: (@escaping (SettingsSnapshot) -> Void) -> Void
    var addModelFromURL: (String, @escaping (SettingsSnapshot) -> Void) -> Void
    var deleteModel: (String, @escaping (SettingsSnapshot) -> Void) -> Void
    var openModelsFolder: () -> Void
    var resetStats: () -> Void

    static let mock = SettingsActions(
        snapshot: { .mock },
        setLaunchAtLogin: { _ in },
        setShowsMenuBarIcon: { _ in },
        setHotkey: { _ in },
        setModel: { _ in },
        setLanguageMode: { _ in },
        checkUpdates: { completion in completion(.mock) },
        updateModels: { completion in completion(.mock) },
        addModelFromURL: { _, completion in completion(.mock) },
        deleteModel: { _, completion in completion(.mock) },
        openModelsFolder: {},
        resetStats: {}
    )
}

final class SettingsViewModel: ObservableObject {
    @Published private(set) var snapshot: SettingsSnapshot

    let hotkeyOptions: [HotkeyMode]

    private let actions: SettingsActions

    init(
        actions: SettingsActions = .mock,
        hotkeyOptions: [HotkeyMode] = HotkeyMode.allCases
    ) {
        self.actions = actions
        self.hotkeyOptions = hotkeyOptions
        self.snapshot = actions.snapshot()
    }

    func reload() {
        snapshot = actions.snapshot()
    }

    func applyLaunchAtLogin(_ enabled: Bool) {
        actions.setLaunchAtLogin(enabled)
        reload()
    }

    func applyShowsMenuBarIcon(_ enabled: Bool) {
        actions.setShowsMenuBarIcon(enabled)
        reload()
    }

    func applyHotkey(_ rawValue: String) {
        actions.setHotkey(rawValue)
        reload()
    }

    func applyModel(_ rawValue: String) {
        actions.setModel(rawValue)
        reload()
    }

    func applyLanguageMode(_ rawValue: String) {
        actions.setLanguageMode(rawValue)
        reload()
    }

    func resetStats() {
        actions.resetStats()
        reload()
    }
}

private enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general
    case models
    case stats

    var title: String {
        switch self {
        case .general:
            return "Общие"
        case .models:
            return "Модели"
        case .stats:
            return "Статистика"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .models:
            return "square.stack.3d.up"
        case .stats:
            return "chart.bar"
        }
    }

    var id: String { rawValue }
}

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    @AppStorage("voice_input_launch_at_login") private var launchAtLogin = false
    @AppStorage("voice_input_show_menu_bar_icon") private var showsMenuBarIcon = true
    @AppStorage("voice_input_hotkey_mode") private var hotkey = HotkeyMode.shiftOption.rawValue
    @AppStorage("voice_input_transcribe_model") private var selectedModelID = TranscribeModel.mediumQ5.rawValue
    @AppStorage("voice_input_language_mode") private var languageMode = LanguageMode.auto.rawValue
    @AppStorage("qualityMode") private var qualityMode = QualityMode.balanced.rawValue
    @AppStorage("voice_input_max_recording_seconds") private var maxRecordingSeconds = 20.0

    @State private var selectedTab: SettingsTab? = .general
    @StateObject private var modelManager: ModelManager

    private let recordingLimitOptions: [Double] = [10, 15, 20, 30, 45, 60]

    init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
        _modelManager = StateObject(wrappedValue: ModelManager(onActiveModelChanged: { modelID in
            viewModel.applyModel(modelID)
        }))
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .listStyle(.sidebar)
        } detail: {
            detailView
        }
        .frame(minWidth: 860, minHeight: 680)
        .onAppear {
            viewModel.reload()
            syncStorageFromSnapshot()
            modelManager.refresh()
            modelManager.syncExternalSelection(viewModel.snapshot.selectedModelID)
        }
        .onReceive(viewModel.$snapshot) { _ in
            syncStorageFromSnapshot()
            modelManager.syncExternalSelection(viewModel.snapshot.selectedModelID)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab ?? .general {
        case .general:
            generalTab
        case .models:
            ModelsView(manager: modelManager)
        case .stats:
            StatisticsView(stats: viewModel.snapshot.stats) {
                viewModel.resetStats()
            }
        }
    }

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VISpacing.xl) {
                SettingsSection("Общие") {
                    SettingsToggleRow(
                        title: "Запуск при входе",
                        value: Binding(
                            get: { launchAtLogin },
                            set: { newValue in
                                launchAtLogin = newValue
                                viewModel.applyLaunchAtLogin(newValue)
                            }
                        )
                    )

                    SettingsToggleRow(
                        title: "Показывать в menu bar",
                        value: Binding(
                            get: { showsMenuBarIcon },
                            set: { newValue in
                                showsMenuBarIcon = newValue
                                viewModel.applyShowsMenuBarIcon(newValue)
                            }
                        )
                    )

                    SettingsPickerRow(
                        title: "Горячая клавиша",
                        selection: selectedHotkeyBinding,
                        options: viewModel.hotkeyOptions,
                        optionTitle: { $0.title }
                    )

                    SettingsPickerRow(
                        title: "Язык",
                        selection: selectedLanguageBinding,
                        options: LanguageMode.allCases,
                        optionTitle: { $0.title }
                    )

                    SettingsShortcutRow(
                        title: "Обучение правок",
                        shortcut: "⌃ ⌃"
                    )
                }

                SettingsSection("Модель") {
                    SettingsRow("Активная модель") {
                        Text(activeModelTitle)
                            .font(VITypography.rowValue)
                            .foregroundStyle(.secondary)
                    }

                    SettingsRow("Размер") {
                        Text(modelSizeBadgeText ?? "—")
                            .font(VITypography.rowValue)
                            .foregroundStyle(.secondary)
                    }

                    SettingsRow("Установлено") {
                        Text(installedModelsText)
                            .font(VITypography.rowHint)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsSection("Качество") {
                    SettingsPickerRow(
                        title: "Режим качества",
                        selection: qualityModeBinding,
                        options: QualityMode.allCases,
                        optionTitle: { qualityTitle($0) }
                    )

                    SettingsPickerRow(
                        title: "Лимит диктовки",
                        selection: $maxRecordingSeconds,
                        options: recordingLimitOptions,
                        optionTitle: { "\(Int($0)) сек" }
                    )
                }
            }
            .padding(VISpacing.xl)
            .frame(width: VIConstants.settingsWidth, alignment: .leading)
        }
    }

    private var activeModelTitle: String {
        guard let descriptor = modelManager.activeModelDescriptor else {
            return "Не выбрана"
        }
        return "\(descriptor.displayName) (\(descriptor.quant))"
    }

    private var modelSizeBadgeText: String? {
        guard let descriptor = modelManager.activeModelDescriptor else {
            return nil
        }
        return "≈ \(descriptor.approxSizeMB) MB"
    }

    private var installedModelsText: String {
        let count = modelManager.installedModelIDs.count
        if count == 1 {
            return "1 модель"
        }
        return "\(count) моделей"
    }

    private var selectedHotkeyBinding: Binding<HotkeyMode> {
        Binding(
            get: { HotkeyMode(rawValue: hotkey) ?? .shiftOption },
            set: { newValue in
                hotkey = newValue.rawValue
                viewModel.applyHotkey(newValue.rawValue)
            }
        )
    }

    private var selectedLanguageBinding: Binding<LanguageMode> {
        Binding(
            get: { LanguageMode(rawValue: languageMode) ?? .auto },
            set: { newValue in
                languageMode = newValue.rawValue
                viewModel.applyLanguageMode(newValue.rawValue)
            }
        )
    }

    private var qualityModeBinding: Binding<QualityMode> {
        Binding(
            get: { QualityMode(rawValue: qualityMode) ?? .balanced },
            set: { newValue in
                qualityMode = newValue.rawValue
            }
        )
    }

    private func qualityTitle(_ mode: QualityMode) -> String {
        switch mode {
        case .fast:
            return "Fast"
        case .balanced:
            return "Balanced"
        case .high:
            return "High"
        }
    }

    private func syncStorageFromSnapshot() {
        launchAtLogin = viewModel.snapshot.launchAtLoginEnabled
        showsMenuBarIcon = viewModel.snapshot.showsMenuBarIcon
        hotkey = viewModel.snapshot.selectedHotkey
        selectedModelID = viewModel.snapshot.selectedModelID
        languageMode = viewModel.snapshot.selectedLanguageMode
    }
}
