import Foundation

@MainActor
protocol TranscriptionEngine {
    func transcribe(audioURL: URL, profile: DictationProfile, useVAD: Bool) async throws -> String
}

@MainActor
final class WhisperCLITranscriptionEngine: TranscriptionEngine {
    private let modelManager: ModelManager
    private let fileManager = FileManager.default

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    func transcribe(audioURL: URL, profile: DictationProfile, useVAD: Bool) async throws -> String {
        do {
            return try await runWhisper(audioURL: audioURL, profile: profile, useVAD: useVAD)
        } catch TranscriptionError.runtimeFailed(let message) where useVAD {
            let vadFailure = message.localizedCaseInsensitiveContains("failed to process audio")
                || message.localizedCaseInsensitiveContains("GGML_ASSERT")
                || message.localizedCaseInsensitiveContains("vad")
            guard vadFailure else { throw TranscriptionError.runtimeFailed(message) }
            return try await runWhisper(audioURL: audioURL, profile: profile, useVAD: false)
        }
    }

    private func runWhisper(audioURL: URL, profile: DictationProfile, useVAD: Bool) async throws -> String {
        let modelURL = modelManager.path()
        guard fileManager.fileExists(atPath: modelURL.path) else {
            throw TranscriptionError.modelMissing(modelManager.selectedModel.displayName)
        }

        guard let executable = whisperExecutable() else {
            throw TranscriptionError.whisperExecutableMissing
        }

        let outputPrefix = fileManager.temporaryDirectory
            .appendingPathComponent("local-stt-transcript-\(UUID().uuidString)")
        let outputText = outputPrefix.appendingPathExtension("txt")
        defer { try? fileManager.removeItem(at: outputText) }

        var arguments = [
            "-m", modelURL.path,
            "-f", audioURL.path,
            "-otxt",
            "-of", outputPrefix.path,
            "-nt",
            "-np"
        ]

        if useVAD {
            arguments.append("--vad")
        }

        if let language = profile.whisperLanguageArgument {
            arguments += ["-l", language]
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorText = String(data: errorData, encoding: .utf8) ?? "Unknown whisper.cpp error"
            throw TranscriptionError.runtimeFailed(errorText)
        }

        guard fileManager.fileExists(atPath: outputText.path) else {
            throw TranscriptionError.outputMissing
        }

        return try String(contentsOf: outputText, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func whisperExecutable() -> URL? {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("whisper-cli"))
        }
        candidates += [
            root.appendingPathComponent("Vendor/whisper.cpp/build/bin/whisper-cli"),
            root.appendingPathComponent("Vendor/whisper.cpp/build/bin/main"),
            URL(fileURLWithPath: "/opt/homebrew/bin/whisper-cli"),
            URL(fileURLWithPath: "/usr/local/bin/whisper-cli")
        ]
        return candidates.first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

enum TranscriptionError: LocalizedError {
    case modelMissing(String)
    case whisperExecutableMissing
    case runtimeFailed(String)
    case outputMissing

    var errorDescription: String? {
        switch self {
        case .modelMissing(let model):
            return "\(model) is not installed. Download a model in Settings."
        case .whisperExecutableMissing:
            return "whisper.cpp executable was not found. Run scripts/bootstrap_whisper_cpp.sh."
        case .runtimeFailed(let message):
            return "whisper.cpp failed: \(message)"
        case .outputMissing:
            return "whisper.cpp did not produce a transcript file."
        }
    }
}
