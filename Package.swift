// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Overhead",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Overhead", targets: ["OverheadApp"]),
        .library(name: "OverheadCore", targets: ["OverheadCore"]),
    ],
    targets: [
        .target(name: "OverheadCore"),
        .executableTarget(name: "OverheadApp", dependencies: ["OverheadCore"]),
        .testTarget(name: "OverheadCoreTests", dependencies: ["OverheadCore"]),
    ]
)
