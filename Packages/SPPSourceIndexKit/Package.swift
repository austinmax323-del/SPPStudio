// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPSourceIndexKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SPPSourceIndexKit", targets: ["SPPSourceIndexKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore"),
        .package(path: "../SPPHookKit")
    ],
    targets: [
        .target(
            name: "SPPSourceIndexKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPHookKit", package: "SPPHookKit")
            ],
            path: "Sources/SPPSourceIndexKit"
        )
    ]
)
