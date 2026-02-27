import AVFoundation
import Foundation

final class AudioManager {
    static let targetSampleRate: Double = 16_000
    static let maxSeconds: Double = 4.0

    private let engine = AVAudioEngine()
    private let processingQueue = DispatchQueue(label: "voiceinput.audio.processing")
    private let ringBuffer = RingBuffer(capacity: Int(targetSampleRate * maxSeconds))
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private(set) var isRunning: Bool = false
    private(set) var lastRMS: Float = 0

    func start() throws {
        if isRunning { return }

        ringBuffer.clear()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard let mono16k = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw NSError(domain: "VoiceInput", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Unable to create 16k mono format"])
        }

        converter = AVAudioConverter(from: inputFormat, to: mono16k)
        targetFormat = mono16k

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.processingQueue.async {
                self?.consume(buffer: buffer)
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        if !isRunning { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }

    func snapshotSpeechSamples() -> [Float] {
        let raw = ringBuffer.snapshot()
        guard !raw.isEmpty else { return [] }
        let trimmed = trimSilence(raw)
        // Fallback to raw audio if VAD is too aggressive for current mic gain/noise floor.
        let selected = trimmed.count >= 800 ? trimmed : raw
        return normalizeForWhisper(selected)
    }

    private func consume(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: max(1, outCapacity)) else {
            return
        }

        var consumed = false
        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        _ = converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        guard error == nil else { return }
        guard converted.frameLength > 0, let channel = converted.floatChannelData?.pointee else { return }

        let sampleCount = Int(converted.frameLength)
        let pointer = UnsafeBufferPointer(start: channel, count: sampleCount)
        ringBuffer.append(pointer)
        lastRMS = computeRMS(pointer)
    }

    private func computeRMS(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples {
            sum += s * s
        }
        return sqrtf(sum / Float(samples.count))
    }

    private func trimSilence(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let threshold: Float = 0.0025
        let frame = 160 // 10 ms @ 16kHz
        var firstSpeech = -1
        var lastSpeech = -1
        var i = 0

        while i < samples.count {
            let end = min(samples.count, i + frame)
            let slice = samples[i..<end]
            var energy: Float = 0
            for sample in slice {
                energy += sample * sample
            }
            let rms = sqrtf(energy / Float(max(1, slice.count)))
            if rms >= threshold {
                if firstSpeech < 0 {
                    firstSpeech = i
                }
                lastSpeech = end
            }
            i += frame
        }

        guard firstSpeech >= 0, lastSpeech > firstSpeech else {
            return []
        }

        let pad = Int(0.18 * Self.targetSampleRate)
        let from = max(0, firstSpeech - pad)
        let to = min(samples.count, lastSpeech + pad)
        return Array(samples[from..<to])
    }

    private func normalizeForWhisper(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var maxAbs: Float = 0
        for s in samples {
            maxAbs = max(maxAbs, abs(s))
        }
        guard maxAbs > 0 else { return samples }
        let targetPeak: Float = 0.18
        let gain = min(12.0, targetPeak / maxAbs)
        if gain <= 1.01 {
            return samples
        }
        return samples.map { max(-1.0, min(1.0, $0 * gain)) }
    }
}
