// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPIPCModels",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "SPPIPCModels", targets: ["SPPIPCModels"])
    ],
    dependencies: [
        .package(path: "../SPPCore")
    ],
    targets: [
        .target(
            name: "SPPIPCModels",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore")
            ],
            path: "Sources/SPPIPCModels"
        )
    ]
)
