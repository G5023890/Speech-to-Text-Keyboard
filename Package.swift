// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceInputApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VoiceInputApp", targets: ["VoiceInputApp"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceInputApp"
        )
    ]
)
