// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ForgeCore",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ForgeCore", targets: ["ForgeCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")],
    targets: [
        .target(name: "ForgeCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "ForgeCoreTests", dependencies: ["ForgeCore", .product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
