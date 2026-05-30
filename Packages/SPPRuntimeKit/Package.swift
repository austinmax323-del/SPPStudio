// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPRuntimeKit",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "SPPRuntimeKit", targets: ["SPPRuntimeKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore"),
        .package(path: "../SPPIPCModels")
    ],
    targets: [
        .target(
            name: "SPPRuntimeKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPIPCModels", package: "SPPIPCModels")
            ],
            path: "Sources/SPPRuntimeKit"
        )
    ]
)
