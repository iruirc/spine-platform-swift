// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AKit", targets: ["AKit"])
    ],
    dependencies: [
        // WORKSPACE_PKG_MANIFEST_DEPS_BEGIN
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.0.0"),
        // WORKSPACE_PKG_MANIFEST_DEPS_END
    ],
    targets: [
        .target(name: "AKit", dependencies: [
            // WORKSPACE_PKG_TARGET_DEPS_BEGIN
            // WORKSPACE_PKG_TARGET_DEPS_END
        ]),
        .testTarget(name: "AKitTests", dependencies: [
            "AKit",
        ])
    ]
)
