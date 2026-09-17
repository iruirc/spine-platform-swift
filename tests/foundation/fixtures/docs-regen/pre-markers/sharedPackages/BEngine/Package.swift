// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BEngine",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "BEngine", targets: ["BEngine"])
    ],
    dependencies: [
        // Filled by `workspace-init` / `workspace-add` based on deps + external_deps in workspace.yml.
    ],
    targets: [
        .target(name: "BEngine", dependencies: []),
        .testTarget(name: "BEngineTests", dependencies: ["BEngine"])
    ]
)
