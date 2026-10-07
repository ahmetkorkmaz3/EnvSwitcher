// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EnvSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EnvCore", targets: ["EnvCore"]),
    ],
    targets: [
        .target(name: "EnvCore"),
        .testTarget(name: "EnvCoreTests", dependencies: ["EnvCore"]),
    ]
)
