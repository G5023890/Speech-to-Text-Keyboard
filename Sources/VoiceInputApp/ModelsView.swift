import SwiftUI

struct ModelsView: View {
    @ObservedObject var manager: ModelManager

    @State private var deleteCandidate: ModelDescriptor?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VISpacing.xl) {
                SettingsSection("Установленные") {
                    if manager.installedDescriptors.isEmpty {
                        SettingsRow("Модели") {
                            Text("Нет установленных")
                                .font(VITypography.rowHint)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(manager.installedDescriptors) { descriptor in
                            installedRow(descriptor)
                        }
                    }
                }

                SettingsSection("Доступные модели") {
                    if manager.availableDescriptors.isEmpty {
                        SettingsRow("Каталог") {
                            Text("Нет доступных")
                                .font(VITypography.rowHint)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(manager.availableDescriptors) { descriptor in
                            availableRow(descriptor)
                        }
                    }
                }

                SettingsSection("Управление") {
                    SettingsRow("Обновления") {
                        HStack(spacing: VISpacing.s) {
                            Button("Проверить") {
                                manager.checkUpdates()
                            }
                            .buttonStyle(.bordered)
                            .disabled(manager.isCheckingUpdates)

                            if manager.hasUpdates {
                                Button("Обновить все") {
                                    manager.updateAll()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(manager.isUpdatingAll)
                            }
                        }
                    }

                    SettingsRow("Статус") {
                        Text(manager.lastCheckStatus)
                            .font(VITypography.rowHint)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(VISpacing.xl)
            .frame(width: VIConstants.settingsWidth, alignment: .leading)
        }
        .confirmationDialog(
            "Удалить модель?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { show in
                    if !show {
                        deleteCandidate = nil
                    }
                }
            ),
            actions: {
                if let deleteCandidate {
                    Button("Удалить", role: .destructive) {
                        manager.delete(deleteCandidate)
                        self.deleteCandidate = nil
                    }
                }
                Button("Отмена", role: .cancel) {
                    deleteCandidate = nil
                }
            },
            message: {
                if let deleteCandidate {
                    Text("Будет удалена модель \(deleteCandidate.displayName) \(deleteCandidate.quant).")
                }
            }
        )
    }

    private func installedRow(_ descriptor: ModelDescriptor) -> some View {
        let active = manager.isActive(descriptor)
        let downloading = manager.isDownloading(descriptor)
        let updateAvailable = manager.updateAvailableIDs.contains(descriptor.id)

        return SettingsRow("\(descriptor.displayName) (\(descriptor.quant))") {
            HStack(spacing: VISpacing.s) {
                Text(manager.installedSizeText(for: descriptor))
                    .font(VITypography.rowHint)
                    .foregroundStyle(.secondary)

                if active {
                    Text("Активная")
                        .font(VITypography.rowHint)
                        .foregroundStyle(.green)
                }

                if downloading {
                    if let progress = manager.downloadProgress[descriptor.id] {
                        ProgressView(value: progress)
                            .frame(width: 72)
                    }
                    Button("Отменить") {
                        manager.cancelDownload(descriptor)
                    }
                    .buttonStyle(.bordered)
                } else if updateAvailable {
                    Button("Обновить") {
                        manager.update(descriptor)
                    }
                    .buttonStyle(.borderedProminent)
                } else if active {
                    Text("Используется")
                        .font(VITypography.rowHint)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Сделать активной") {
                        manager.setActiveModel(descriptor)
                    }
                    .buttonStyle(.bordered)

                    Button("Удалить") {
                        deleteCandidate = descriptor
                    }
                    .buttonStyle(.bordered)
                    .disabled(!manager.canDelete(descriptor))
                }
            }
        }
    }

    private func availableRow(_ descriptor: ModelDescriptor) -> some View {
        let downloading = manager.isDownloading(descriptor)

        return SettingsRow("\(descriptor.displayName) (\(descriptor.quant))") {
            HStack(spacing: VISpacing.s) {
                if descriptor.recommended {
                    Text("Рекомендуется")
                        .font(VITypography.rowHint)
                        .foregroundStyle(.blue)
                }

                Text("\(descriptor.approxSizeMB) MB")
                    .font(VITypography.rowHint)
                    .foregroundStyle(.secondary)

                if downloading {
                    if let progress = manager.downloadProgress[descriptor.id] {
                        ProgressView(value: progress)
                            .frame(width: 72)
                    }
                    Button("Отменить") {
                        manager.cancelDownload(descriptor)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("Установить") {
                        manager.install(descriptor)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
