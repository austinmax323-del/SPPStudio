// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPSymbolKit",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "SPPSymbolKit", targets: ["SPPSymbolKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore")
    ],
    targets: [
        .target(
            name: "SPPSymbolKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore")
            ],
            path: "Sources/SPPSymbolKit"
        )
    ]
)
