// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPHookKit",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "SPPHookKit", targets: ["SPPHookKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore")
    ],
    targets: [
        .target(
            name: "SPPHookKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore")
            ],
            path: "Sources/SPPHookKit"
        )
    ]
)
