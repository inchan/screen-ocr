// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ScreenOCR",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ScreenOCRCore", targets: ["ScreenOCRCore"]),
        .executable(name: "ScreenOCRApp", targets: ["ScreenOCRApp"]),
        .executable(name: "ScreenOCRSmoke", targets: ["ScreenOCRSmoke"]),
        .executable(name: "ScreenOCRFixtureWindow", targets: ["ScreenOCRFixtureWindow"])
    ],
    targets: [
        .target(name: "ScreenOCRCore"),
        .executableTarget(
            name: "ScreenOCRApp",
            dependencies: ["ScreenOCRCore"]
        ),
        .executableTarget(
            name: "ScreenOCRSmoke",
            dependencies: ["ScreenOCRCore"]
        ),
        .executableTarget(
            name: "ScreenOCRFixtureWindow"
        ),
        .testTarget(
            name: "ScreenOCRCoreTests",
            dependencies: ["ScreenOCRCore"]
        )
    ]
)
