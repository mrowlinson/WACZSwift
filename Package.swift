// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WACZSwift",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "WACZSwift", targets: ["WACZSwift"]),
        .executable(name: "wacz", targets: ["wacz"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "CZlib",
            dependencies: [],
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "WACZSwift",
            dependencies: [
                "CZlib",
                "ZIPFoundation",
                "SwiftSoup",
            ]
        ),
        .executableTarget(
            name: "wacz",
            dependencies: [
                "WACZSwift",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "WACZSwiftTests",
            dependencies: ["WACZSwift"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
