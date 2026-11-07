// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeqatCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MeqatCore", targets: ["MeqatCore"])],
    targets: [
        .target(name: "MeqatCore", resources: [.process("Resources")]),
        .testTarget(
            name: "MeqatCoreTests",
            dependencies: ["MeqatCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
