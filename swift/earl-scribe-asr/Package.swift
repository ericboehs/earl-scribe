// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "earl-scribe-asr",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "earl-scribe-asr", targets: ["earl-scribe-asr"])
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.14.1"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "earl-scribe-asr",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
