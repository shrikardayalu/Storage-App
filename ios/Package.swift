// swift-tools-version:5.9
// SwiftPM manifest used only by xtool, to build and install the app from Linux or
// WSL (see XTOOL_SETUP.md). The Mac build still comes from project.yml via XcodeGen
// and ignores this file.
//
// xtool can't compile asset catalogs off macOS, so Resources/ (Assets.xcassets) is
// excluded here. xtool builds therefore show no illustrations; the app icon is
// supplied separately through xtool.yml.

import PackageDescription

let package = Package(
    name: "StorageApp",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "StorageApp", targets: ["StorageApp"]),
    ],
    dependencies: [
        .package(path: "StorageCore"),
    ],
    targets: [
        .target(
            name: "StorageApp",
            dependencies: [
                .product(name: "StorageCore", package: "StorageCore"),
            ],
            path: "StorageApp",
            // Info.plist exists only after `xcodegen generate` on a Mac.
            exclude: ["Resources", "Info.plist"]
        ),
    ],
    // Matches SWIFT_VERSION 5.0 in project.yml.
    swiftLanguageVersions: [.v5]
)
