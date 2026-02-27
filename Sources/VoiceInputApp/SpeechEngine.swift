import CWhisper
import Foundation

enum QualityMode: String, CaseIterable {
    case fast
    case balanced
    case high
}

enum TranscriptionPass {
    case partial
    case final
}

struct TranscriptionOutput {
    let text: String
    let detectedLanguageCode: String?
    let confidence: Float
}

actor SpeechEngine {
    static let shared = SpeechEngine()

    private var context: OpaquePointer?
    private var finalState: OpaquePointer?
    private var partialState: OpaquePointer?
    private var loadedModelPath: String?
    private var adaptiveLanguageHint: String?
    private var languageStreakCode: String?
    private var languageStreakCount: Int = 0

    func warmup(modelPath: String) async throws {
        try ensureContext(modelPath: modelPath)
    }

    func transcribe(
        samples: [Float],
        modelPath: String,
        languageMode: LanguageMode,
        pass: TranscriptionPass
    ) async throws -> TranscriptionOutput {
        guard !samples.isEmpty else {
            return TranscriptionOutput(text: "", detectedLanguageCode: nil, confidence: 0)
        }

        try ensureContext(modelPath: modelPath)
        guard let context else {
            throw NSError(domain: "VoiceInput", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Whisper context is not ready"])
        }
        let state: OpaquePointer?
        switch pass {
        case .partial:
            state = partialState
        case .final:
            state = finalState
        }
        guard let state else {
            throw NSError(domain: "VoiceInput", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Whisper state is not ready"])
        }

        let hint = resolveHint(for: languageMode)
        let qualityMode = currentQualityMode()
        var params = makeParams(pass: pass, qualityMode: qualityMode)

        let copiedHint = hint.flatMap { strdup($0) }
        var autoLanguage: UnsafeMutablePointer<CChar>?
        defer {
            if let copiedHint {
                free(copiedHint)
            }
            if let autoLanguage {
                free(autoLanguage)
            }
        }

        if let copiedHint {
            params.language = UnsafePointer(copiedHint)
            params.detect_language = false
        } else {
            autoLanguage = strdup("auto")
            params.language = UnsafePointer(autoLanguage)
            params.detect_language = true
        }

        let rc = samples.withUnsafeBufferPointer { ptr in
            whisper_full_with_state(context, state, params, ptr.baseAddress, Int32(ptr.count))
        }
        guard rc == 0 else {
            throw NSError(domain: "VoiceInput", code: 2002, userInfo: [NSLocalizedDescriptionKey: "whisper_full_with_state failed"])
        }

        let text = collectText(from: state)
        let detectedCode = detectedLanguageCode(from: state)
        let confidence = averageConfidence(from: state)

        if pass == .final {
            updateAdaptiveState(mode: languageMode, detectedCode: detectedCode, confidence: confidence)
        }

        return TranscriptionOutput(
            text: text,
            detectedLanguageCode: detectedCode,
            confidence: confidence
        )
    }

    private func currentQualityMode() -> QualityMode {
        let raw = UserDefaults.standard.string(forKey: "qualityMode") ?? QualityMode.balanced.rawValue
        return QualityMode(rawValue: raw) ?? .balanced
    }

    private func makeParams(pass: TranscriptionPass, qualityMode: QualityMode) -> whisper_full_params {
        let strategy: whisper_sampling_strategy = {
            switch pass {
            case .partial:
                return WHISPER_SAMPLING_GREEDY
            case .final:
                return qualityMode == .high ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
            }
        }()
        var params = whisper_full_default_params(strategy)
        params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))
        params.no_timestamps = true
        params.suppress_blank = true
        params.temperature = 0
        params.suppress_nst = false
        params.max_tokens = 0
        params.audio_ctx = 0

        switch pass {
        case .partial:
            params.greedy.best_of = 1
            params.no_context = true
            params.single_segment = true
        case .final:
            switch qualityMode {
            case .fast:
                params.greedy.best_of = 1
                params.no_context = true
                params.single_segment = true
            case .balanced:
                params.greedy.best_of = 3
                params.no_context = false
                params.single_segment = false
            case .high:
                params.beam_search.beam_size = 4
                params.no_context = false
                params.single_segment = false
            }
        }
        return params
    }

    private func ensureContext(modelPath: String) throws {
        if context != nil, loadedModelPath == modelPath {
            return
        }
        unloadContext()

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        cparams.gpu_device = 0

        guard let ctx = whisper_init_from_file_with_params(modelPath, cparams) else {
            throw NSError(domain: "VoiceInput", code: 2003, userInfo: [NSLocalizedDescriptionKey: "Failed to load model: \(modelPath)"])
        }
        guard let stFinal = whisper_init_state(ctx) else {
            whisper_free(ctx)
            throw NSError(domain: "VoiceInput", code: 2004, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize whisper state"])
        }
        guard let stPartial = whisper_init_state(ctx) else {
            whisper_free_state(stFinal)
            whisper_free(ctx)
            throw NSError(domain: "VoiceInput", code: 2004, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize partial whisper state"])
        }

        context = ctx
        finalState = stFinal
        partialState = stPartial
        loadedModelPath = modelPath
    }

    private func unloadContext() {
        if let finalState {
            whisper_free_state(finalState)
            self.finalState = nil
        }
        if let partialState {
            whisper_free_state(partialState)
            self.partialState = nil
        }
        if let context {
            whisper_free(context)
            self.context = nil
        }
        loadedModelPath = nil
    }

    private func resolveHint(for mode: LanguageMode) -> String? {
        switch mode {
        case .auto:
            return adaptiveLanguageHint
        case .russian, .english, .hebrew:
            return mode.whisperLanguageCode
        }
    }

    private func collectText(from state: OpaquePointer) -> String {
        let segments = Int(whisper_full_n_segments_from_state(state))
        guard segments > 0 else { return "" }
        var parts: [String] = []
        parts.reserveCapacity(segments)
        for i in 0..<segments {
            if let cText = whisper_full_get_segment_text_from_state(state, Int32(i)) {
                let value = String(cString: cText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    parts.append(value)
                }
            }
        }
        return parts.joined(separator: " ")
    }

    private func detectedLanguageCode(from state: OpaquePointer) -> String? {
        let id = whisper_full_lang_id_from_state(state)
        guard id >= 0 else { return nil }
        guard let cCode = whisper_lang_str(id) else { return nil }
        let code = String(cString: cCode)
        switch code {
        case "ru", "en", "he":
            return code
        default:
            return nil
        }
    }

    private func averageConfidence(from state: OpaquePointer) -> Float {
        let segments = Int(whisper_full_n_segments_from_state(state))
        guard segments > 0 else { return 0 }
        var sum: Float = 0
        var n: Int = 0
        for segment in 0..<segments {
            let tokenCount = Int(whisper_full_n_tokens_from_state(state, Int32(segment)))
            for token in 0..<tokenCount {
                sum += whisper_full_get_token_p_from_state(state, Int32(segment), Int32(token))
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        return sum / Float(n)
    }

    private func updateAdaptiveState(mode: LanguageMode, detectedCode: String?, confidence: Float) {
        guard mode == .auto else {
            adaptiveLanguageHint = nil
            languageStreakCode = nil
            languageStreakCount = 0
            return
        }

        guard confidence >= 0.55, let detectedCode else {
            adaptiveLanguageHint = nil
            languageStreakCode = nil
            languageStreakCount = 0
            return
        }

        if detectedCode == languageStreakCode {
            languageStreakCount += 1
        } else {
            languageStreakCode = detectedCode
            languageStreakCount = 1
        }

        if languageStreakCount >= 3 {
            adaptiveLanguageHint = detectedCode
        }
    }
}
