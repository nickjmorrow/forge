// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ForgeUI",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [.library(name: "ForgeUI", targets: ["ForgeUI"])],
    dependencies: [.package(path: "../Core")],
    targets: [
        .target(name: "ForgeUI", dependencies: [.product(name: "ForgeCore", package: "Core")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ForgeUITests", dependencies: ["ForgeUI", .product(name: "ForgeCore", package: "Core")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
