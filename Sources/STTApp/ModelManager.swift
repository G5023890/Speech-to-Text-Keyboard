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
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var selectedModel: WhisperModel = .small
    @Published private(set) var downloadProgress: Double?
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

    func isInstalled(_ model: WhisperModel) -> Bool {
        fileManager.fileExists(atPath: path(for: model).path)
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
