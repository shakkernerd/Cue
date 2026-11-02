// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cue", targets: ["Cue"]),
    ],
    targets: [
        .target(name: "CueCore"),
        .executableTarget(name: "Cue", dependencies: ["CueCore"]),
        .testTarget(name: "CueCoreTests", dependencies: ["CueCore"]),
    ]
)
