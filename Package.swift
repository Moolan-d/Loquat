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
    ],
    swiftLanguageModes: [.v6]
)
