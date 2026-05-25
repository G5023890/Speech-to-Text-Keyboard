import AppKit
import Foundation

struct TrainingCounts: Equatable {
    var mixedRuEn: Int = 0
    var hebrew: Int = 0

    func count(for profile: DictationProfile) -> Int {
        switch profile {
        case .mixedRuEn:
            return mixedRuEn
        case .hebrew:
            return hebrew
        }
    }
}

struct TrainingExampleMetadata: Codable {
    let id: String
    let profile: String
    let transcript: String
    let audioFilename: String
    let modelName: String
    let createdAt: Date
    let schemaVersion: Int
}

struct TrainedModel: Codable, Identifiable, Hashable {
    let id: String
    let displayName: String
    let modelFilename: String
    let coreMLEncoderDirectoryName: String?
    let importedAt: Date
}

@MainActor
final class TrainingStore: ObservableObject {
    @Published private(set) var counts = TrainingCounts()
    @Published private(set) var trainedModels: [TrainedModel] = []
    @Published var useTrainedModel = false
    @Published var selectedTrainedModelID: String?
    @Published private(set) var lastMessage: String?

    private let fileManager = FileManager.default

    private var baseDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LocalSTT/Training", isDirectory: true)
    }

    private var examplesDirectory: URL {
        baseDirectory.appendingPathComponent("Examples", isDirectory: true)
    }

    private var trainedModelsDirectory: URL {
        baseDirectory.appendingPathComponent("TrainedModels", isDirectory: true)
    }

    private var indexURL: URL {
        trainedModelsDirectory.appendingPathComponent("trained-models.json")
    }

    init() {
        refresh()
    }

    func refresh() {
        counts = TrainingCounts(
            mixedRuEn: countExamples(for: .mixedRuEn),
            hebrew: countExamples(for: .hebrew)
        )
        trainedModels = loadTrainedModels()
        if let selectedTrainedModelID, !trainedModels.contains(where: { $0.id == selectedTrainedModelID }) {
            self.selectedTrainedModelID = nil
        }
        if selectedTrainedModelID == nil {
            selectedTrainedModelID = trainedModels.first?.id
        }
        if trainedModels.isEmpty {
            useTrainedModel = false
        }
    }

    func selectedTrainedModelURL() -> URL? {
        guard useTrainedModel, let selectedTrainedModel else { return nil }
        return trainedModelsDirectory
            .appendingPathComponent(selectedTrainedModel.id, isDirectory: true)
            .appendingPathComponent(selectedTrainedModel.modelFilename)
    }

    var selectedTrainedModel: TrainedModel? {
        guard let selectedTrainedModelID else { return nil }
        return trainedModels.first { $0.id == selectedTrainedModelID }
    }

    func saveExample(audioURL: URL, transcript: String, profile: DictationProfile, modelName: String) throws {
        let id = UUID().uuidString
        let directory = examplesDirectory
            .appendingPathComponent(profile.storageName, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let audioDestination = directory.appendingPathComponent("audio.wav")
        if fileManager.fileExists(atPath: audioDestination.path) {
            try fileManager.removeItem(at: audioDestination)
        }
        try fileManager.moveItem(at: audioURL, to: audioDestination)

        let metadata = TrainingExampleMetadata(
            id: id,
            profile: profile.rawValue,
            transcript: transcript.trimmingCharacters(in: .whitespacesAndNewlines),
            audioFilename: "audio.wav",
            modelName: modelName,
            createdAt: Date(),
            schemaVersion: 1
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: directory.appendingPathComponent("metadata.json"))
        lastMessage = "Saved training example"
        refresh()
    }

    func exportDataset() throws -> URL {
        let exportRoot = baseDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent("localstt-dataset-\(Self.timestamp())", isDirectory: true)
        let audioRoot = exportRoot.appendingPathComponent("audio", isDirectory: true)
        try fileManager.createDirectory(at: audioRoot, withIntermediateDirectories: true)

        var rows: [String] = ["audio,transcription,profile,model_name,created_at"]
        for profile in DictationProfile.allCases {
            let examples = try loadExamples(for: profile)
            for (metadata, directory) in examples {
                let audioName = "\(profile.storageName)-\(metadata.id).wav"
                let audioDestination = audioRoot.appendingPathComponent(audioName)
                try fileManager.copyItem(
                    at: directory.appendingPathComponent(metadata.audioFilename),
                    to: audioDestination
                )
                rows.append([
                    "audio/\(audioName)",
                    metadata.transcript,
                    profile.rawValue,
                    metadata.modelName,
                    ISO8601DateFormatter().string(from: metadata.createdAt)
                ].map(Self.csvEscape).joined(separator: ","))
            }
        }

        try rows.joined(separator: "\n").write(
            to: exportRoot.appendingPathComponent("metadata.csv"),
            atomically: true,
            encoding: .utf8
        )

        let readme = """
        # Local STT Fine-Tune Dataset

        Format: Hugging Face-compatible CSV with columns `audio`, `transcription`, `profile`, `model_name`, `created_at`.

        Load with `datasets.load_dataset("csv", data_files="metadata.csv")` and cast `audio` to `Audio`.
        """
        try readme.write(to: exportRoot.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        NSWorkspace.shared.activateFileViewerSelecting([exportRoot])
        lastMessage = "Exported dataset"
        return exportRoot
    }

    func importTrainedModel(modelURL: URL, coreMLEncoderURL: URL?) throws {
        guard modelURL.pathExtension == "bin" else {
            throw TrainingStoreError.invalidModel
        }

        let id = "trained-\(Self.timestamp())"
        let directory = trainedModelsDirectory.appendingPathComponent(id, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        var importCompleted = false
        defer {
            if !importCompleted {
                try? fileManager.removeItem(at: directory)
            }
        }

        let modelDestination = directory.appendingPathComponent(modelURL.lastPathComponent)
        try fileManager.copyItem(at: modelURL, to: modelDestination)

        var encoderName: String?
        if let coreMLEncoderURL {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: coreMLEncoderURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw TrainingStoreError.invalidCoreMLEncoder
            }
            encoderName = modelURL.deletingPathExtension().lastPathComponent + "-encoder.mlmodelc"
            try fileManager.copyItem(at: coreMLEncoderURL, to: directory.appendingPathComponent(encoderName!, isDirectory: true))
        }

        try validateModel(at: modelDestination)

        let model = TrainedModel(
            id: id,
            displayName: modelURL.deletingPathExtension().lastPathComponent,
            modelFilename: modelURL.lastPathComponent,
            coreMLEncoderDirectoryName: encoderName,
            importedAt: Date()
        )
        trainedModels.append(model)
        selectedTrainedModelID = model.id
        useTrainedModel = false
        try saveTrainedModels()
        importCompleted = true
        lastMessage = "Imported trained model"
        refresh()
    }

    func resetTraining() throws {
        if fileManager.fileExists(atPath: baseDirectory.path) {
            try fileManager.removeItem(at: baseDirectory)
        }
        lastMessage = "Training data reset"
        refresh()
    }

    private func countExamples(for profile: DictationProfile) -> Int {
        let directory = examplesDirectory.appendingPathComponent(profile.storageName, isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return 0
        }
        return contents.filter { fileManager.fileExists(atPath: $0.appendingPathComponent("metadata.json").path) }.count
    }

    private func loadExamples(for profile: DictationProfile) throws -> [(TrainingExampleMetadata, URL)] {
        let directory = examplesDirectory.appendingPathComponent(profile.storageName, isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try contents.compactMap { exampleDirectory in
            let metadataURL = exampleDirectory.appendingPathComponent("metadata.json")
            guard fileManager.fileExists(atPath: metadataURL.path) else { return nil }
            let metadata = try decoder.decode(TrainingExampleMetadata.self, from: Data(contentsOf: metadataURL))
            return (metadata, exampleDirectory)
        }
    }

    private func loadTrainedModels() -> [TrainedModel] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? JSONDecoder().decode([TrainedModel].self, from: data)) ?? []
    }

    private func saveTrainedModels() throws {
        try fileManager.createDirectory(at: trainedModelsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(trainedModels).write(to: indexURL)
    }

    private func validateModel(at modelURL: URL) throws {
        guard let executableURL = whisperExecutable() else {
            throw TrainingStoreError.whisperExecutableMissing
        }

        let audioURL = fileManager.temporaryDirectory
            .appendingPathComponent("localstt-validate-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        defer { try? fileManager.removeItem(at: audioURL) }
        try Self.writeSilentWav(to: audioURL)

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-nt",
            "-np",
            "-l", "auto"
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "Unknown validation error"
            throw TrainingStoreError.validationFailed(message)
        }
    }

    private func whisperExecutable() -> URL? {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("whisper-cli"))
        }
        candidates += [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Vendor/whisper.cpp/build/bin/whisper-cli"),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }

    private static func csvEscape(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func writeSilentWav(to url: URL) throws {
        let sampleRate = 16_000
        let samples = sampleRate / 4
        let dataSize = samples * 2
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(sampleRate * 2).littleEndianData)
        data.append(UInt16(2).littleEndianData)
        data.append(UInt16(16).littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(UInt32(dataSize).littleEndianData)
        data.append(Data(repeating: 0, count: dataSize))
        try data.write(to: url)
    }
}

enum TrainingStoreError: LocalizedError {
    case invalidModel
    case invalidCoreMLEncoder
    case whisperExecutableMissing
    case validationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidModel:
            return "Select a fine-tuned .bin model."
        case .invalidCoreMLEncoder:
            return "Select a Core ML encoder .mlmodelc folder."
        case .whisperExecutableMissing:
            return "whisper.cpp executable was not found, so the trained model could not be validated."
        case .validationFailed(let message):
            return "The trained model failed validation: \(message)"
        }
    }
}

private extension UInt16 {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}

private extension UInt32 {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

private extension DictationProfile {
    var storageName: String {
        switch self {
        case .mixedRuEn:
            return "ru-en"
        case .hebrew:
            return "hebrew"
        }
    }
}
