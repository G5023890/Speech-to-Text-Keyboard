// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInputApp",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "VoiceInputApp", targets: ["VoiceInputApp"])
    ],
    targets: [
        .systemLibrary(
            name: "CWhisper",
            path: "Sources/CWhisper"
        ),
        .executableTarget(
            name: "VoiceInputApp",
            dependencies: ["CWhisper"],
            swiftSettings: [
                .unsafeFlags([
                    "-Xcc",
                    "-I/opt/homebrew/opt/whisper-cpp/include",
                    "-Xcc",
                    "-I/opt/homebrew/opt/ggml/include"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L/opt/homebrew/opt/whisper-cpp/lib",
                    "-L/opt/homebrew/opt/ggml/lib",
                    "-lwhisper",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/opt/homebrew/opt/whisper-cpp/lib",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/opt/homebrew/opt/ggml/lib"
                ])
            ]
        )
    ]
)
