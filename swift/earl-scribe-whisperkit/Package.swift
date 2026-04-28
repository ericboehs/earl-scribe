// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "earl-scribe-whisperkit",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "earl-scribe-whisperkit", targets: ["earl-scribe-whisperkit"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "earl-scribe-whisperkit",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
