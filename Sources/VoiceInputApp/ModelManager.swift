import Combine
import Foundation

@MainActor
final class ModelManager: ObservableObject {
    private struct ActiveDownload {
        let task: URLSessionDownloadTask
        let observation: NSKeyValueObservation
    }

    private struct RemoteMetadata {
        let contentLength: Int64?
        let etag: String?
    }

    private struct DownloadResult {
        let tempURL: URL
        let response: HTTPURLResponse?
    }

    @Published var searchText = ""
    @Published private(set) var selectedModelID: String?
    @Published private(set) var installedModelIDs: Set<String> = []
    @Published private(set) var updateAvailableIDs: Set<String> = []
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var failedModels: [String: String] = [:]
    @Published private(set) var isCheckingUpdates = false
    @Published private(set) var isUpdatingAll = false
    @Published private(set) var lastCheckStatus = "Проверка обновлений не выполнялась"

    let catalog: [ModelDescriptor]

    private var registry: ModelsRegistry = .empty
    private var activeDownloads: [String: ActiveDownload] = [:]

    private let store: ModelStore
    private let session: URLSession
    private let userDefaults: UserDefaults
    private let selectedModelDefaultsKey: String
    private let onActiveModelChanged: (String) -> Void

    init(
        store: ModelStore = ModelStore(),
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        selectedModelDefaultsKey: String = "voice_input_transcribe_model",
        onActiveModelChanged: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
        self.session = session
        self.userDefaults = userDefaults
        self.selectedModelDefaultsKey = selectedModelDefaultsKey
        self.onActiveModelChanged = onActiveModelChanged
        self.catalog = ModelCatalog.models
        refresh()
    }

    var hasUpdates: Bool {
        !updateAvailableIDs.isEmpty
    }

    var activeModelDescriptor: ModelDescriptor? {
        guard let selectedModelID else {
            return nil
        }
        return catalog.first(where: { $0.id == selectedModelID })
    }

    var installedDescriptors: [ModelDescriptor] {
        filteredDescriptors.filter { installedModelIDs.contains($0.id) }
    }

    var availableDescriptors: [ModelDescriptor] {
        filteredDescriptors.filter { !installedModelIDs.contains($0.id) }
    }

    func refresh() {
        Task {
            await reloadFromDisk()
        }
    }

    func syncExternalSelection(_ modelID: String) {
        guard installedModelIDs.contains(modelID), selectedModelID != modelID else {
            return
        }
        selectedModelID = modelID
        registry.selectedModelID = modelID
        persistRegistry()
    }

    func isInstalled(_ descriptor: ModelDescriptor) -> Bool {
        installedModelIDs.contains(descriptor.id)
    }

    func isActive(_ descriptor: ModelDescriptor) -> Bool {
        selectedModelID == descriptor.id
    }

    func isDownloading(_ descriptor: ModelDescriptor) -> Bool {
        activeDownloads[descriptor.id] != nil
    }

    func isFailed(_ descriptor: ModelDescriptor) -> Bool {
        failedModels[descriptor.id] != nil
    }

    func statusText(for descriptor: ModelDescriptor) -> String {
        if let progress = downloadProgress[descriptor.id] {
            return "Downloading \(Int(progress * 100))%"
        }
        if failedModels[descriptor.id] != nil {
            return "Failed"
        }
        if updateAvailableIDs.contains(descriptor.id) {
            return "Update available"
        }
        return installedModelIDs.contains(descriptor.id) ? "Installed" : "Not installed"
    }

    func installedSizeText(for descriptor: ModelDescriptor) -> String {
        guard let record = registry.installedModels[descriptor.id] else {
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: record.sizeBytes, countStyle: .file)
    }

    func canDelete(_ descriptor: ModelDescriptor) -> Bool {
        isInstalled(descriptor) && !isActive(descriptor) && !isDownloading(descriptor)
    }

    func setActiveModel(_ descriptor: ModelDescriptor) {
        guard isInstalled(descriptor) else {
            return
        }
        selectedModelID = descriptor.id
        registry.selectedModelID = descriptor.id
        persistRegistry()
        onActiveModelChanged(descriptor.id)
    }

    func install(_ descriptor: ModelDescriptor) {
        Task {
            await installOrUpdate(descriptor)
        }
    }

    func update(_ descriptor: ModelDescriptor) {
        Task {
            await installOrUpdate(descriptor)
        }
    }

    func cancelDownload(_ descriptor: ModelDescriptor) {
        activeDownloads[descriptor.id]?.task.cancel()
    }

    func delete(_ descriptor: ModelDescriptor) {
        guard canDelete(descriptor) else {
            return
        }
        Task {
            await deleteInstalledModel(descriptor)
        }
    }

    func checkUpdates() {
        guard !isCheckingUpdates else {
            return
        }
        Task {
            await checkUpdatesAsync()
        }
    }

    func updateAll() {
        guard !isUpdatingAll else {
            return
        }
        let targets = catalog.filter { updateAvailableIDs.contains($0.id) && installedModelIDs.contains($0.id) }
        guard !targets.isEmpty else {
            return
        }
        Task {
            isUpdatingAll = true
            for descriptor in targets {
                await installOrUpdate(descriptor)
            }
            isUpdatingAll = false
            await checkUpdatesAsync()
        }
    }

    private var filteredDescriptors: [ModelDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return catalog
        }
        return catalog.filter {
            $0.displayName.lowercased().contains(query) ||
                $0.quant.lowercased().contains(query) ||
                $0.fileName.lowercased().contains(query)
        }
    }

    private func reloadFromDisk() async {
        do {
            let previousSelected = selectedModelID
            try await store.ensureDirectoryStructure()
            registry = try await store.loadRegistry()
            registry.installedModels = try await reconciledInstalledRecords(from: registry.installedModels)
            selectedModelID = resolvedSelection(
                selectedFromRegistry: registry.selectedModelID,
                selectedFromDefaults: userDefaults.string(forKey: selectedModelDefaultsKey),
                installedIDs: Set(registry.installedModels.keys)
            )
            registry.selectedModelID = selectedModelID
            persistRegistry()
            if let selectedModelID, selectedModelID != previousSelected {
                onActiveModelChanged(selectedModelID)
            }
        } catch {
            lastCheckStatus = "Ошибка загрузки каталога: \(error.localizedDescription)"
        }
    }

    private func reconciledInstalledRecords(from existing: [String: InstalledModelRecord]) async throws -> [String: InstalledModelRecord] {
        var records: [String: InstalledModelRecord] = [:]
        for descriptor in catalog {
            guard let size = await store.installedFileSize(fileName: descriptor.fileName), size > 0 else {
                continue
            }
            let previous = existing[descriptor.id]
            records[descriptor.id] = InstalledModelRecord(
                fileName: descriptor.fileName,
                relativePath: "Models/\(descriptor.fileName)",
                sizeBytes: size,
                etag: previous?.etag,
                installedAt: previous?.installedAt ?? Date()
            )
        }
        return records
    }

    private func resolvedSelection(
        selectedFromRegistry: String?,
        selectedFromDefaults: String?,
        installedIDs: Set<String>
    ) -> String? {
        if let selectedFromRegistry, installedIDs.contains(selectedFromRegistry) {
            return selectedFromRegistry
        }
        if let selectedFromDefaults, installedIDs.contains(selectedFromDefaults) {
            return selectedFromDefaults
        }
        if let recommended = catalog.first(where: { $0.recommended && installedIDs.contains($0.id) }) {
            return recommended.id
        }
        return installedIDs.sorted().first
    }

    private func persistRegistry() {
        installedModelIDs = Set(registry.installedModels.keys)
        if let selectedModelID {
            userDefaults.set(selectedModelID, forKey: selectedModelDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: selectedModelDefaultsKey)
        }
        Task { [registry, store] in
            try? await store.saveRegistry(registry)
        }
    }

    private func installOrUpdate(_ descriptor: ModelDescriptor) async {
        guard activeDownloads[descriptor.id] == nil else {
            return
        }

        failedModels[descriptor.id] = nil
        updateAvailableIDs.remove(descriptor.id)

        do {
            let remoteMeta = try await fetchRemoteMetadata(for: descriptor)
            let request = URLRequest(url: descriptor.downloadURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 1200)
            let result = try await downloadModel(descriptor, request: request)
            let responseMeta = metadata(from: result.response)
            let expected = responseMeta.contentLength ?? remoteMeta.contentLength
            let finalEtag = responseMeta.etag ?? remoteMeta.etag

            let sizeBytes = try await store.installDownloadedFile(
                tempURL: result.tempURL,
                fileName: descriptor.fileName,
                expectedSize: expected
            )

            registry.installedModels[descriptor.id] = InstalledModelRecord(
                fileName: descriptor.fileName,
                relativePath: "Models/\(descriptor.fileName)",
                sizeBytes: sizeBytes,
                etag: finalEtag,
                installedAt: Date()
            )

            let wasSelectedMissing = selectedModelID == nil || !installedModelIDs.contains(selectedModelID ?? "")
            installedModelIDs.insert(descriptor.id)
            if wasSelectedMissing {
                selectedModelID = descriptor.id
                registry.selectedModelID = descriptor.id
                onActiveModelChanged(descriptor.id)
            }
            persistRegistry()
        } catch is CancellationError {
            await store.clearPartFile(fileName: descriptor.fileName)
        } catch {
            failedModels[descriptor.id] = error.localizedDescription
            await store.clearPartFile(fileName: descriptor.fileName)
        }
    }

    private func deleteInstalledModel(_ descriptor: ModelDescriptor) async {
        do {
            try await store.removeInstalledModel(fileName: descriptor.fileName)
            registry.installedModels.removeValue(forKey: descriptor.id)
            installedModelIDs.remove(descriptor.id)
            updateAvailableIDs.remove(descriptor.id)
            failedModels.removeValue(forKey: descriptor.id)

            if selectedModelID == descriptor.id {
                selectedModelID = resolvedSelection(
                    selectedFromRegistry: nil,
                    selectedFromDefaults: userDefaults.string(forKey: selectedModelDefaultsKey),
                    installedIDs: installedModelIDs
                )
                registry.selectedModelID = selectedModelID
                if let selectedModelID {
                    onActiveModelChanged(selectedModelID)
                }
            }
            persistRegistry()
        } catch {
            failedModels[descriptor.id] = error.localizedDescription
        }
    }

    private func checkUpdatesAsync() async {
        guard !isCheckingUpdates else {
            return
        }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }

        var updateIDs: Set<String> = []
        var checked = 0

        for descriptor in catalog where installedModelIDs.contains(descriptor.id) {
            guard let local = registry.installedModels[descriptor.id] else {
                continue
            }
            do {
                let remote = try await fetchRemoteMetadata(for: descriptor)
                checked += 1
                if isRemoteDifferent(local: local, remote: remote) {
                    updateIDs.insert(descriptor.id)
                }
            } catch {
                continue
            }
        }

        updateAvailableIDs = updateIDs
        let now = Date().formatted(date: .abbreviated, time: .shortened)
        if updateIDs.isEmpty {
            lastCheckStatus = checked == 0 ? "Нет установленных моделей для проверки" : "Обновлений нет • \(now)"
        } else {
            lastCheckStatus = "Доступно обновлений: \(updateIDs.count) • \(now)"
        }
    }

    private func fetchRemoteMetadata(for descriptor: ModelDescriptor) async throws -> RemoteMetadata {
        var request = URLRequest(url: descriptor.downloadURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 60)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return metadata(from: http)
    }

    private func metadata(from response: HTTPURLResponse?) -> RemoteMetadata {
        guard let response else {
            return RemoteMetadata(contentLength: nil, etag: nil)
        }
        let contentLengthRaw = response.value(forHTTPHeaderField: "Content-Length")
        let contentLength = contentLengthRaw.flatMap { Int64($0) }
        let etag = response.value(forHTTPHeaderField: "ETag")?.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return RemoteMetadata(contentLength: contentLength, etag: etag)
    }

    private func isRemoteDifferent(local: InstalledModelRecord, remote: RemoteMetadata) -> Bool {
        if let remoteLength = remote.contentLength, remoteLength > 0, remoteLength != local.sizeBytes {
            return true
        }
        if let remoteEtag = remote.etag?.lowercased(), let localEtag = local.etag?.lowercased(), remoteEtag != localEtag {
            return true
        }
        return false
    }

    private func downloadModel(_ descriptor: ModelDescriptor, request: URLRequest) async throws -> DownloadResult {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { [weak self] tempURL, response, error in
                Task { @MainActor in
                    guard let self else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.cleanupDownload(for: descriptor.id)

                    if let error {
                        if let urlError = error as? URLError, urlError.code == .cancelled {
                            continuation.resume(throwing: CancellationError())
                            return
                        }
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let tempURL else {
                        continuation.resume(throwing: URLError(.cannotDecodeContentData))
                        return
                    }
                    continuation.resume(
                        returning: DownloadResult(
                            tempURL: tempURL,
                            response: response as? HTTPURLResponse
                        )
                    )
                }
            }

            let observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                Task { @MainActor [weak self] in
                    self?.downloadProgress[descriptor.id] = progress.fractionCompleted
                }
            }

            activeDownloads[descriptor.id] = ActiveDownload(task: task, observation: observation)
            downloadProgress[descriptor.id] = 0
            task.resume()
        }
    }

    private func cleanupDownload(for modelID: String) {
        activeDownloads.removeValue(forKey: modelID)
        downloadProgress.removeValue(forKey: modelID)
    }
}
