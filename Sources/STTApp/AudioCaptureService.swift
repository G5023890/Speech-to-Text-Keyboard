import AVFoundation
import Foundation

@MainActor
final class AudioCaptureService: NSObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func start() throws {
        cancel()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-stt-\(UUID().uuidString)")
            .appendingPathExtension("wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw AudioCaptureError.failedToStart
        }

        self.recorder = recorder
        currentURL = url
    }

    func stop() throws -> URL {
        guard let recorder, let url = currentURL else {
            throw AudioCaptureError.noActiveRecording
        }
        recorder.stop()
        self.recorder = nil
        currentURL = nil
        return url
    }

    func cancel() {
        recorder?.stop()
        recorder = nil
        if let currentURL {
            try? FileManager.default.removeItem(at: currentURL)
        }
        currentURL = nil
    }
}

enum AudioCaptureError: LocalizedError {
    case failedToStart
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .failedToStart:
            return "Could not start microphone recording."
        case .noActiveRecording:
            return "No active recording was found."
        }
    }
}
