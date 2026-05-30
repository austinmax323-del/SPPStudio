// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPUIBuilderKit",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "SPPUIBuilderKit", targets: ["SPPUIBuilderKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore")
    ],
    targets: [
        .target(
            name: "SPPUIBuilderKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore")
            ],
            path: "Sources/SPPUIBuilderKit"
        )
    ]
)
