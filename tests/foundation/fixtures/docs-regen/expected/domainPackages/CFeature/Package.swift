// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "CFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CFeature", targets: ["CFeature"])
    ],
    dependencies: [
        // WORKSPACE_PKG_MANIFEST_DEPS_BEGIN
        .package(path: "../../sharedPackages/AKit"),
        .package(path: "../../sharedPackages/BEngine"),
        // WORKSPACE_PKG_MANIFEST_DEPS_END
    ],
    targets: [
        .target(name: "CFeature", dependencies: [
            // WORKSPACE_PKG_TARGET_DEPS_BEGIN
            .product(name: "AKit", package: "AKit"),
            .product(name: "BEngine", package: "BEngine"),
            // WORKSPACE_PKG_TARGET_DEPS_END
        ]),
        .testTarget(name: "CFeatureTests", dependencies: [
            "CFeature",
        ])
    ]
)
