// swift-tools-version: 6.0
//
// ProximiioGADKit: the Guggenheim Abu Dhabi museum map, journey (map and list) and wristband
// screens, built on the Proximi.io iOS SDK and Map. See README.md.
//
// The SDK and the Map are published binaries pinned to an exact version. The map package
// pins the same SDK version, so both are bumped together.
import PackageDescription

let package = Package(
    name: "ProximiioGADKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ProximiioGADKit", targets: ["ProximiioGADKit"]),
        // The Live Activity attributes and widget, for the host app's widget extension.
        .library(name: "ProximiioGADLiveActivity", targets: ["ProximiioGADLiveActivity"]),
    ],
    dependencies: [
        .package(url: "https://github.com/proximiio/proximiio-sdk-ios-binary", exact: "6.0.0-beta.57"),
        .package(url: "https://github.com/proximiio/proximiio-map-ios-binary", exact: "6.0.0-beta.42"),
    ],
    targets: [
        .target(name: "ProximiioGADLiveActivity"),
        .target(
            name: "ProximiioGADKit",
            dependencies: [
                "ProximiioGADLiveActivity",
                .product(name: "Proximiio", package: "proximiio-sdk-ios-binary"),
                .product(name: "ProximiioMap", package: "proximiio-map-ios-binary"),
            ],
            // Fonts, icons, screen backgrounds, level change animations and the English and
            // Arabic strings.
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ProximiioGADKitTests",
            dependencies: [
                "ProximiioGADKit",
                .product(name: "Proximiio", package: "proximiio-sdk-ios-binary"),
                .product(name: "ProximiioMap", package: "proximiio-map-ios-binary"),
            ]
        ),
    ]
)
