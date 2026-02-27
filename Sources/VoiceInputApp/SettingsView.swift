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
    @AppStorage("voice_input_hotkey_mode") private var hotkey = HotkeyMode.shiftOption.rawValue
    @AppStorage("voice_input_transcribe_model") private var selectedModelID = TranscribeModel.mediumQ5.rawValue
    @AppStorage("voice_input_language_mode") private var languageMode = LanguageMode.auto.rawValue
    @AppStorage("qualityMode") private var qualityMode = QualityMode.balanced.rawValue

    @State private var selectedTab: SettingsTab? = .general
    @StateObject private var modelManager: ModelManager

    private let pickerWidth: CGFloat = 280

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
            modelsTab
        case .stats:
            statsTab
        }
    }

    private var generalTab: some View {
        Form {
            Section("Общие") {
                Toggle("Запуск при входе", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        viewModel.applyLaunchAtLogin(newValue)
                    }
                ))
                .padding(.vertical, 2)

                LabeledContent("Горячая клавиша") {
                    Picker("", selection: Binding(
                        get: { hotkey },
                        set: { newValue in
                            hotkey = newValue
                            viewModel.applyHotkey(newValue)
                        }
                    )) {
                        ForEach(viewModel.hotkeyOptions, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.large)
                    .frame(width: pickerWidth)
                }
                .padding(.vertical, 2)

                LabeledContent("Язык") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Picker("", selection: Binding(
                            get: { languageMode },
                            set: { newValue in
                                languageMode = newValue
                                viewModel.applyLanguageMode(newValue)
                            }
                        )) {
                            ForEach(LanguageMode.allCases, id: \.rawValue) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.large)
                        .frame(width: pickerWidth)

                        Text("Определяет язык распознавания")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                LabeledContent("Режим качества") {
                    VStack(alignment: .trailing, spacing: 4) {
                        Picker("", selection: $qualityMode) {
                            Text("Fast").tag(QualityMode.fast.rawValue)
                            Text("Balanced").tag(QualityMode.balanced.rawValue)
                            Text("High").tag(QualityMode.high.rawValue)
                        }
                        .labelsHidden()
                        .controlSize(.large)
                        .frame(width: pickerWidth)

                        Text("Влияет на скорость и точность финального распознавания")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("Модель") {
                LabeledContent("Активная модель") {
                    HStack(spacing: 10) {
                        Text(activeModelTitle)
                        if let modelSizeBadgeText {
                            Text(modelSizeBadgeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.quaternary))
                        }
                    }
                }
                .padding(.vertical, 2)

                LabeledContent("") {
                    Text(installedModelsText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
                .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private var modelsTab: some View {
        Form {
            Section {
                ModelsSettingsView(manager: modelManager)
                    .padding(.vertical, 2)
            }
        }
        .formStyle(.grouped)
        .padding(24)
    }

    private var statsTab: some View {
        Form {
            Section("Статистика") {
                Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                    statsGridRow("Сегодня", formattedStatsValue(seconds: viewModel.snapshot.stats.todaySeconds, words: viewModel.snapshot.stats.todayWords))
                    statsGridRow("Неделя", viewModel.snapshot.stats.hasWeeklyAggregate ? formattedStatsValue(seconds: viewModel.snapshot.stats.weekSeconds, words: viewModel.snapshot.stats.weekWords) : "—")
                    statsGridRow("Месяц", viewModel.snapshot.stats.hasMonthlyAggregate ? formattedStatsValue(seconds: viewModel.snapshot.stats.monthSeconds, words: viewModel.snapshot.stats.monthWords) : "—")
                    statsGridRow("Всего", viewModel.snapshot.stats.hasTotalAggregate ? formattedDuration(viewModel.snapshot.stats.totalSeconds) : "—")
                }

                Text("\(viewModel.snapshot.stats.sessions) диктовок • \(viewModel.snapshot.stats.words) слов")
                    .foregroundStyle(.secondary)

                Button("Сбросить статистику", role: .destructive) {
                    viewModel.resetStats()
                }
                .buttonStyle(.bordered)
            }
        }
        .formStyle(.grouped)
        .padding(24)
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
            return "Установлена 1 модель"
        }
        return "Установлено \(count) моделей"
    }

    private func statsGridRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
            Text(value).monospacedDigit()
        }
    }

    private func formattedStatsValue(seconds: Double, words: Int) -> String {
        return "\(formattedDuration(seconds)) • \(words.formatted()) слов"
    }

    private func syncStorageFromSnapshot() {
        launchAtLogin = viewModel.snapshot.launchAtLoginEnabled
        hotkey = viewModel.snapshot.selectedHotkey
        selectedModelID = viewModel.snapshot.selectedModelID
        languageMode = viewModel.snapshot.selectedLanguageMode
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            return "\(hours)ч \(String(format: "%02d", minutes))м"
        }
        if minutes > 0 {
            return "\(minutes)м \(String(format: "%02d", secs))с"
        }
        return "\(secs)с"
    }
}
