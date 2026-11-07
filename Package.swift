// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DictateLocal",
    platforms: [.macOS("26.0")],
    dependencies: [
        // Pinned on purpose: the Nemotron Unified port is new and its API is still moving.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", revision: "6924debcefeb0c52aa48350ef2e7f0ce0ce4e700"),
        // Its FoundationModels integration needs macOS 27, so that trait stays off.
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3", traits: [])
    ],
    targets: [
        .target(
            name: "DictateCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DictateLocal",
            dependencies: ["DictateCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DictateChecks",
            dependencies: ["DictateCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
