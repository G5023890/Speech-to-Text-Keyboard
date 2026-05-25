import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var manager: ModelManager

    @State private var deleteCandidate: ModelDescriptor?

    var body: some View {
        VStack(spacing: 16) {
            topBar

            List {
                Section("Установленные") {
                    if manager.installedDescriptors.isEmpty {
                        Text("Нет установленных моделей")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.installedDescriptors) { descriptor in
                            modelRow(descriptor)
                        }
                    }
                }

                Section("Доступные") {
                    if manager.availableDescriptors.isEmpty {
                        Text("Нет доступных моделей по текущему фильтру")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(manager.availableDescriptors) { descriptor in
                            modelRow(descriptor)
                        }
                    }
                }
            }
            .listStyle(.inset)

            HStack {
                Text(manager.lastCheckStatus)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Spacer()
            }
        }
        .padding(24)
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
                    Text("Будет удалена модель \(deleteCandidate.displayName) \(deleteCandidate.quant) (\(manager.installedSizeText(for: deleteCandidate))).")
                }
            }
        )
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Поиск по имени или quant", text: $manager.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .frame(maxWidth: 360)

            Spacer(minLength: 12)

            Button("Проверить обновления") {
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

    private func modelRow(_ descriptor: ModelDescriptor) -> some View {
        let installed = manager.isInstalled(descriptor)
        let active = manager.isActive(descriptor)
        let downloading = manager.isDownloading(descriptor)
        let failed = manager.isFailed(descriptor)
        let updateAvailable = manager.updateAvailableIDs.contains(descriptor.id)

        return HStack(spacing: 12) {
            if active {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(descriptor.displayName)
                        .font(.body.weight(.semibold))
                    Text(descriptor.quant)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(nsColor: .controlBackgroundColor)))
                    Text("\(descriptor.approxSizeMB) MB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if descriptor.recommended {
                        Text("Рекомендуется")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                            .foregroundStyle(Color.accentColor)
                    }
                    if active {
                        Text("Активная")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.green.opacity(0.16)))
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 8) {
                    Text(manager.statusText(for: descriptor))
                        .font(.callout)
                        .foregroundStyle(failed ? .red : .secondary)

                    if downloading, let progress = manager.downloadProgress[descriptor.id] {
                        ProgressView(value: progress)
                            .frame(width: 140)
                    }
                }

                if installed && active {
                    Text("Сначала выберите другую модель")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            if downloading {
                Button("Отменить") {
                    manager.cancelDownload(descriptor)
                }
                .buttonStyle(.bordered)
            } else if installed {
                if updateAvailable {
                    Button("Обновить") {
                        manager.update(descriptor)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Удалить") {
                        deleteCandidate = descriptor
                    }
                    .buttonStyle(.bordered)
                    .disabled(!manager.canDelete(descriptor))
                }
            } else {
                Button("Установить") {
                    manager.install(descriptor)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if installed {
                manager.setActiveModel(descriptor)
            }
        }
        .padding(.vertical, 4)
    }
}
