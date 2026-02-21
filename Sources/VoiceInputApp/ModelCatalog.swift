import Foundation

struct ModelDescriptor: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let fileName: String
    let displayName: String
    let quant: String
    let approxSizeMB: Int
    let recommended: Bool

    var downloadURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }
}

enum ModelCatalog {
    static let minAllowedSizeMB = 150
    static let maxAllowedSizeMB = 600

    private static let embedded: [ModelDescriptor] = [
        ModelDescriptor(
            id: "ggml-large-v3-turbo-q4_K_M",
            fileName: "ggml-large-v3-turbo-q4_K_M.bin",
            displayName: "Large v3 Turbo",
            quant: "q4_K_M",
            approxSizeMB: 503,
            recommended: true
        ),
        ModelDescriptor(
            id: "ggml-medium-q5_0",
            fileName: "ggml-medium-q5_0.bin",
            displayName: "Medium",
            quant: "q5_0",
            approxSizeMB: 515,
            recommended: false
        ),
        ModelDescriptor(
            id: "ggml-small-q8_0",
            fileName: "ggml-small-q8_0.bin",
            displayName: "Small",
            quant: "q8_0",
            approxSizeMB: 257,
            recommended: false
        ),
        ModelDescriptor(
            id: "ggml-small-q5_1",
            fileName: "ggml-small-q5_1.bin",
            displayName: "Small",
            quant: "q5_1",
            approxSizeMB: 193,
            recommended: false
        ),
        ModelDescriptor(
            id: "ggml-medium-q4_0",
            fileName: "ggml-medium-q4_0.bin",
            displayName: "Medium",
            quant: "q4_0",
            approxSizeMB: 394,
            recommended: false
        )
    ]

    static let models: [ModelDescriptor] = embedded
        .filter { (minAllowedSizeMB...maxAllowedSizeMB).contains($0.approxSizeMB) }
        .sorted { lhs, rhs in
            if lhs.recommended != rhs.recommended {
                return lhs.recommended && !rhs.recommended
            }
            if lhs.displayName != rhs.displayName {
                return lhs.displayName < rhs.displayName
            }
            return lhs.quant < rhs.quant
        }

    static func descriptor(for id: String) -> ModelDescriptor? {
        models.first(where: { $0.id == id })
    }
}
