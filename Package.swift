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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .target(name: "ScreenOCRCore"),
        .executableTarget(
            name: "ScreenOCRApp",
            dependencies: [
                "ScreenOCRCore",
                .product(name: "Sparkle", package: "Sparkle")
            ]
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
