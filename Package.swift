// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "nelko",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "NelkoCore", targets: ["NelkoCore"]),
        .executable(name: "nelko", targets: ["nelko"]),
    ],
    targets: [
        .target(name: "NativeRFCOMM", path: "Sources/NativeRFCOMM", publicHeadersPath: "include", linkerSettings: [.linkedFramework("IOBluetooth")]),
        .target(name: "NelkoCore", dependencies: ["NativeRFCOMM"]),
        .executableTarget(name: "nelko", dependencies: ["NelkoCore"]),
        .executableTarget(name: "nelko-tests", dependencies: ["NelkoCore"], path: "Tests/NelkoCoreTests"),
    ]
)
