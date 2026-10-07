// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EnvSwitcher",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EnvCore", targets: ["EnvCore"]),
        .executable(name: "EnvSwitcher", targets: ["EnvSwitcher"]),
    ],
    targets: [
        .target(name: "EnvCore"),
        .executableTarget(
            name: "EnvSwitcher",
            dependencies: ["EnvCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "EnvCoreTests", dependencies: ["EnvCore"]),
    ]
)
