// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "forge",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(path: "../Core"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(name: "forge", dependencies: [
            .product(name: "ForgeCore", package: "Core"),
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "forgeTests", dependencies: ["forge", .product(name: "ForgeCore", package: "Core")]),
    ]
)
