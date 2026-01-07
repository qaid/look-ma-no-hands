// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WhisperTalk",
    platforms: [
        .macOS(.v14)  // Minimum macOS 14 (Sonoma) for @Observable macro
    ],
    products: [
        .executable(
            name: "WhisperTalk",
            targets: ["WhisperTalk"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "WhisperTalk",
            dependencies: [
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ],
            path: "Sources/WhisperTalk",
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                // Required frameworks for macOS system integration
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Accelerate")
            ]
        ),
        .testTarget(
            name: "WhisperTalkTests",
            dependencies: ["WhisperTalk"]
        )
    ]
)
