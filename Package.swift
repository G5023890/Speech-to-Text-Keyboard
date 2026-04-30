// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalSTT",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LocalSTT", targets: ["STTApp"])
    ],
    targets: [
        .executableTarget(
            name: "STTApp",
            path: "Sources/STTApp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
