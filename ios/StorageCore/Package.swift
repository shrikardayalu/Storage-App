// swift-tools-version:5.9
// StorageCore holds the app's platform-independent business logic: media and
// storage models, scan grouping, storage history, compression estimates, and the
// service protocols (with mocks for tests). It depends only on Foundation, so
// `swift test` runs on macOS, Linux, and Windows without Xcode.

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
