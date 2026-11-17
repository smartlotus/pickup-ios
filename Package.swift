// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PickupCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "PickupCore",
            targets: ["PickupCore"]
        ),
    ],
    targets: [
        .target(
            name: "PickupCore",
            path: "Sources/PickupCore",
            linkerSettings: [
                .linkedLibrary("z"),
            ]
        ),
        .testTarget(
            name: "PickupCoreTests",
            dependencies: ["PickupCore"],
            path: "Tests/PickupCoreTests"
        ),
    ]
)
