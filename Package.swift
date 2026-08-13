// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InstantTranslation",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "InstantTranslationCore", targets: ["InstantTranslationCore"]),
        .library(
            name: "InstantTranslationInfrastructure",
            targets: ["InstantTranslationInfrastructure"]
        ),
        .library(name: "InstantTranslationFeature", targets: ["InstantTranslationFeature"]),
        .library(name: "InstantTranslationApp", targets: ["InstantTranslationApp"]),
        .executable(name: "InstantTranslation", targets: ["InstantTranslation"]),
        .executable(
            name: "InstantTranslationDiagnostics",
            targets: ["InstantTranslationDiagnostics"]
        ),
    ],
    targets: [
        .target(name: "InstantTranslationCore"),
        .testTarget(
            name: "InstantTranslationCoreTests",
            dependencies: ["InstantTranslationCore"]
        ),
        .target(
            name: "InstantTranslationInfrastructure",
            dependencies: ["InstantTranslationCore"]
        ),
        .testTarget(
            name: "InstantTranslationInfrastructureTests",
            dependencies: ["InstantTranslationInfrastructure", "InstantTranslationCore"]
        ),
        .target(
            name: "InstantTranslationFeature",
            dependencies: ["InstantTranslationCore", "InstantTranslationInfrastructure"]
        ),
        .testTarget(
            name: "InstantTranslationFeatureTests",
            dependencies: ["InstantTranslationFeature", "InstantTranslationCore"]
        ),
        .target(
            name: "InstantTranslationApp",
            dependencies: [
                "InstantTranslationCore",
                "InstantTranslationInfrastructure",
                "InstantTranslationFeature",
            ],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "InstantTranslation",
            dependencies: ["InstantTranslationApp"]
        ),
        .executableTarget(
            name: "InstantTranslationDiagnostics",
            dependencies: [
                "InstantTranslationApp",
                "InstantTranslationFeature",
                "InstantTranslationCore",
                "InstantTranslationInfrastructure",
            ]
        ),
        .testTarget(
            name: "InstantTranslationAppTests",
            dependencies: [
                "InstantTranslationApp",
                "InstantTranslationFeature",
                "InstantTranslationCore",
                "InstantTranslationInfrastructure",
            ]
        ),
        .testTarget(
            name: "InstantTranslationDiagnosticsTests",
            dependencies: ["InstantTranslationDiagnostics"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
