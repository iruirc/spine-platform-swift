// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "BEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BEngine", targets: ["BEngine"])
    ],
    dependencies: [
        // WORKSPACE_PKG_MANIFEST_DEPS_BEGIN
        .package(path: "../AKit"),
        // WORKSPACE_PKG_MANIFEST_DEPS_END
    ],
    targets: [
        .target(name: "BEngine", dependencies: [
            // WORKSPACE_PKG_TARGET_DEPS_BEGIN
            .product(name: "AKit", package: "AKit"),
            // WORKSPACE_PKG_TARGET_DEPS_END
        ]),
        .testTarget(name: "BEngineTests", dependencies: [
            "BEngine",
        ])
    ]
)
