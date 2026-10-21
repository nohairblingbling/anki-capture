// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AnkiCapture",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CaptureCore", targets: ["CaptureCore"]),
        .executable(name: "anki-capture", targets: ["CaptureCLI"]),
        .executable(name: "AnkiCapture", targets: ["CaptureApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "CaptureCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .executableTarget(name: "CaptureCLI", dependencies: ["CaptureCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "CaptureApp", dependencies: ["CaptureCore"]),
        .testTarget(name: "CaptureCoreTests", dependencies: ["CaptureCore"])
    ],
    swiftLanguageModes: [.v5]
)
