// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HotspotKeeper",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "HotspotKeeper", targets: ["HotspotKeeper"])
    ],
    targets: [
        .executableTarget(name: "HotspotKeeper")
    ]
)
