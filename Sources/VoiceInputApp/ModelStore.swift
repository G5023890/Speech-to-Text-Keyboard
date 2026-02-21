import Foundation

struct InstalledModelRecord: Codable, Hashable, Sendable {
    let fileName: String
    let relativePath: String
    let sizeBytes: Int64
    let etag: String?
    let installedAt: Date
}

struct ModelsRegistry: Codable, Hashable, Sendable {
    var selectedModelID: String?
    var installedModels: [String: InstalledModelRecord]
    var localImports: [String: String]?

    static let empty = ModelsRegistry(
        selectedModelID: nil,
        installedModels: [:],
        localImports: nil
    )
}

enum ModelStoreError: LocalizedError {
    case invalidContentLength(expected: Int64, actual: Int64)
    case registrySaveFailed

    var errorDescription: String? {
        switch self {
        case .invalidContentLength(let expected, let actual):
            return "Размер файла не совпадает (ожидалось \(expected), получено \(actual))."
        case .registrySaveFailed:
            return "Не удалось сохранить реестр моделей."
        }
    }
}

actor ModelStore {
    let baseURL: URL
    let modelsURL: URL
    let downloadsURL: URL
    let catalogURL: URL
    let registryURL: URL

    private let fileManager = FileManager.default

    init(baseURL: URL = ModelStore.defaultBaseURL()) {
        self.baseURL = baseURL
        self.modelsURL = baseURL.appendingPathComponent("Models", isDirectory: true)
        self.downloadsURL = baseURL.appendingPathComponent("Downloads", isDirectory: true)
        self.catalogURL = baseURL.appendingPathComponent("Catalog", isDirectory: true)
        self.registryURL = baseURL.appendingPathComponent("models-registry.json", isDirectory: false)
    }

    static func defaultBaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Voice Input", isDirectory: true)
    }

    func ensureDirectoryStructure() throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: catalogURL, withIntermediateDirectories: true)
    }

    func loadRegistry() throws -> ModelsRegistry {
        try ensureDirectoryStructure()
        guard fileManager.fileExists(atPath: registryURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: registryURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ModelsRegistry.self, from: data)
    }

    func saveRegistry(_ registry: ModelsRegistry) throws {
        try ensureDirectoryStructure()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(registry)
        let temporaryURL = registryURL.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        do {
            if fileManager.fileExists(atPath: registryURL.path) {
                _ = try fileManager.replaceItemAt(registryURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: registryURL)
            }
        } catch {
            throw ModelStoreError.registrySaveFailed
        }
    }

    func installedFileURL(fileName: String) -> URL {
        modelsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func partFileURL(fileName: String) -> URL {
        downloadsURL.appendingPathComponent(fileName + ".part", isDirectory: false)
    }

    func installedFileSize(fileName: String) -> Int64? {
        let url = installedFileURL(fileName: fileName)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    func installDownloadedFile(tempURL: URL, fileName: String, expectedSize: Int64?) throws -> Int64 {
        try ensureDirectoryStructure()

        let destinationURL = installedFileURL(fileName: fileName)
        let partURL = partFileURL(fileName: fileName)
        let stagingURL = downloadsURL.appendingPathComponent(fileName + ".staging", isDirectory: false)

        try? fileManager.removeItem(at: partURL)
        try? fileManager.removeItem(at: stagingURL)

        try fileManager.moveItem(at: tempURL, to: partURL)

        let partAttributes = try fileManager.attributesOfItem(atPath: partURL.path)
        let partSize = (partAttributes[.size] as? NSNumber)?.int64Value ?? 0
        if let expectedSize, expectedSize > 0, partSize != expectedSize {
            try? fileManager.removeItem(at: partURL)
            throw ModelStoreError.invalidContentLength(expected: expectedSize, actual: partSize)
        }

        try fileManager.moveItem(at: partURL, to: stagingURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            _ = try fileManager.replaceItemAt(destinationURL, withItemAt: stagingURL)
        } else {
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
        }

        let finalAttributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        return (finalAttributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    func removeInstalledModel(fileName: String) throws {
        let target = installedFileURL(fileName: fileName)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
    }

    func clearPartFile(fileName: String) {
        let part = partFileURL(fileName: fileName)
        try? fileManager.removeItem(at: part)
        let staging = downloadsURL.appendingPathComponent(fileName + ".staging", isDirectory: false)
        try? fileManager.removeItem(at: staging)
    }
}
