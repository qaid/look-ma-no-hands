// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LookMaNoHands",
    platforms: [
        .macOS(.v14)  // Minimum macOS 14 (Sonoma) for @Observable macro
    ],
    products: [
        .executable(
            name: "LookMaNoHands",
            targets: ["LookMaNoHands"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/exPHAT/SwiftWhisper.git",
                 revision: "a192004db08de7c6eaa169eede77f1625e7d23fb")
    ],
    targets: [
        .executableTarget(
            name: "LookMaNoHands",
            dependencies: [
                .product(name: "SwiftWhisper", package: "SwiftWhisper")
            ],
            path: "Sources/LookMaNoHands",
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
            name: "LookMaNoHandsTests",
            dependencies: ["LookMaNoHands"]
        )
    ]
)
