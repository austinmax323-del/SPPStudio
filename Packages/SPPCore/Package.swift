// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPCore",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "SPPCore", targets: ["SPPCore"])
    ],
    targets: [
        .target(
            name: "SPPCore",
            path: "Sources/SPPCore"
        ),
        .testTarget(
            name: "SPPCoreTests",
            dependencies: ["SPPCore"],
            path: "Tests/SPPCoreTests"
        )
    ]
)
