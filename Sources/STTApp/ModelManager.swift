import Foundation

enum WhisperModel: String, CaseIterable, Identifiable {
    case small
    case medium

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small:
            return "Whisper Small"
        case .medium:
            return "Whisper Medium"
        }
    }

    var filename: String {
        switch self {
        case .small:
            return "ggml-small.bin"
        case .medium:
            return "ggml-medium.bin"
        }
    }

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    var coreMLEncoderDirectoryName: String {
        filename.replacingOccurrences(of: ".bin", with: "-encoder.mlmodelc")
    }

    var coreMLEncoderZipName: String {
        "\(coreMLEncoderDirectoryName).zip"
    }

    var coreMLEncoderDownloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(coreMLEncoderZipName)")!
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var selectedModel: WhisperModel = .small
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var coreMLDownloadProgress: Double?
    @Published private(set) var lastError: String?

    private let fileManager = FileManager.default

    var modelsDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocalSTT/Models", isDirectory: true)
    }

    func select(_ model: WhisperModel) {
        selectedModel = model
    }

    func path(for model: WhisperModel? = nil) -> URL {
        modelsDirectory.appendingPathComponent((model ?? selectedModel).filename)
    }

    func coreMLEncoderPath(for model: WhisperModel? = nil) -> URL {
        modelsDirectory.appendingPathComponent((model ?? selectedModel).coreMLEncoderDirectoryName, isDirectory: true)
    }

    func isInstalled(_ model: WhisperModel) -> Bool {
        fileManager.fileExists(atPath: path(for: model).path)
    }

    func isCoreMLInstalled(_ model: WhisperModel) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: coreMLEncoderPath(for: model).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func installedModels() -> [WhisperModel] {
        WhisperModel.allCases.filter(isInstalled)
    }

    func download(_ model: WhisperModel) async throws {
        lastError = nil
        downloadProgress = 0
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destination = path(for: model)
        if fileManager.fileExists(atPath: destination.path) {
            selectedModel = model
            downloadProgress = nil
            return
        }

        let temporaryURL = destination.appendingPathExtension("download")
        try? fileManager.removeItem(at: temporaryURL)

        do {
            try await FileDownloader.download(from: model.downloadURL, to: temporaryURL) { [weak self] progress in
                Task { @MainActor in
                    self?.downloadProgress = progress
                }
            }

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: temporaryURL, to: destination)
            selectedModel = model
            downloadProgress = nil
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            downloadProgress = nil
            lastError = error.localizedDescription
            throw error
        }
    }

    func downloadCoreMLEncoder(for model: WhisperModel) async throws {
        lastError = nil
        coreMLDownloadProgress = 0
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        let destination = coreMLEncoderPath(for: model)
        if isCoreMLInstalled(model) {
            coreMLDownloadProgress = nil
            return
        }

        let zipURL = modelsDirectory.appendingPathComponent(model.coreMLEncoderZipName).appendingPathExtension("download")
        let unpackDirectory = modelsDirectory.appendingPathComponent("coreml-\(UUID().uuidString)", isDirectory: true)
        try? fileManager.removeItem(at: zipURL)
        try? fileManager.removeItem(at: unpackDirectory)

        do {
            try await FileDownloader.download(from: model.coreMLEncoderDownloadURL, to: zipURL) { [weak self] progress in
                Task { @MainActor in
                    self?.coreMLDownloadProgress = progress * 0.85
                }
            }
            try fileManager.createDirectory(at: unpackDirectory, withIntermediateDirectories: true)
            try unzip(zipURL: zipURL, destination: unpackDirectory)

            guard let unpacked = try findCoreMLEncoder(named: model.coreMLEncoderDirectoryName, in: unpackDirectory) else {
                throw ModelManagerError.coreMLEncoderMissing(model.coreMLEncoderDirectoryName)
            }

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: unpacked, to: destination)
            coreMLDownloadProgress = nil
        } catch {
            try? fileManager.removeItem(at: zipURL)
            try? fileManager.removeItem(at: unpackDirectory)
            coreMLDownloadProgress = nil
            lastError = error.localizedDescription
            throw error
        }
    }

    private func unzip(zipURL: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Unknown unzip error"
            throw ModelManagerError.unzipFailed(message)
        }
    }

    private func findCoreMLEncoder(named directoryName: String, in root: URL) throws -> URL? {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == directoryName else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                return url
            }
        }
        return nil
    }
}

enum ModelManagerError: LocalizedError {
    case coreMLEncoderMissing(String)
    case unzipFailed(String)

    var errorDescription: String? {
        switch self {
        case .coreMLEncoderMissing(let name):
            return "Downloaded archive did not contain \(name)."
        case .unzipFailed(let message):
            return "Could not unpack Core ML encoder: \(message)"
        }
    }
}

private enum FileDownloader {
    static func download(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        let expectedLength = response.expectedContentLength
        let fileManager = FileManager.default

        fileManager.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer: [UInt8] = []
        buffer.reserveCapacity(256 * 1024)
        var received: Int64 = 0

        func flush() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
            buffer.removeAll(keepingCapacity: true)
            if expectedLength > 0 {
                progress(min(Double(received) / Double(expectedLength), 1))
            }
        }

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 256 * 1024 {
                try flush()
            }
        }

        try flush()
        progress(1)
    }
}
