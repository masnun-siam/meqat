// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeqatCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MeqatCore", targets: ["MeqatCore"])],
    targets: [
        .target(name: "MeqatCore"),
        .testTarget(
            name: "MeqatCoreTests",
            dependencies: ["MeqatCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
