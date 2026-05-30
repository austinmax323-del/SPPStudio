// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPTheosKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SPPTheosKit", targets: ["SPPTheosKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore"),
        .package(path: "../SPPHookKit")
    ],
    targets: [
        .target(
            name: "SPPTheosKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPHookKit", package: "SPPHookKit")
            ],
            path: "Sources/SPPTheosKit"
        )
    ]
)
