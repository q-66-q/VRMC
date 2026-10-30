// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VRMC",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VRMCore", targets: ["VRMCore"]),
        .library(name: "VRMCVideo", targets: ["VRMCVideo"]),
    ],
    targets: [
        .target(
            name: "VRMCore",
            path: "Sources/VRMCore"
        ),
        .target(
            name: "VRMCVideo",
            dependencies: ["VRMCore"],
            path: "Sources/VRMCVideo"
        ),
        .testTarget(
            name: "VRMCoreTests",
            dependencies: ["VRMCore"],
            path: "Tests/VRMCoreTests",
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "VRMCVideoTests",
            dependencies: ["VRMCVideo", "VRMCore"],
            path: "Tests/VRMCVideoTests",
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
