// swift-tools-version:5.9
// StorageCore holds the app's platform-independent business logic: media models,
// the deterministic demo-library generator, compression estimates, and the mock
// media service. It depends only on Foundation, so `swift test` runs on macOS,
// Linux, and Windows without Xcode.

import PackageDescription

let package = Package(
    name: "StorageCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "StorageCore", targets: ["StorageCore"]),
    ],
    targets: [
        .target(name: "StorageCore"),
        .testTarget(name: "StorageCoreTests", dependencies: ["StorageCore"]),
    ]
)
