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
    ],
    swiftLanguageModes: [.v6]
)
