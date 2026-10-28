// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Overhead",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Overhead", targets: ["OverheadApp"]),
        .library(name: "OverheadCore", targets: ["OverheadCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(name: "OverheadCore"),
        .executableTarget(
            name: "OverheadApp",
            dependencies: ["OverheadCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework is copied into Contents/Frameworks by scripts/build-app.sh.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "OverheadCoreTests", dependencies: ["OverheadCore"]),
    ]
)
