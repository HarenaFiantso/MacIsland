// swift-tools-version: 5.9
import PackageDescription

// IslandCore holds the UI-free logic of the island: state machine, geometry,
// spring definitions. It has no AppKit/SwiftUI dependency so it can be unit
// tested in seconds with `swift test`.
let package = Package(
    name: "IslandCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IslandCore", targets: ["IslandCore"]),
    ],
    targets: [
        .target(name: "IslandCore"),
        .testTarget(name: "IslandCoreTests", dependencies: ["IslandCore"]),
    ]
)
