// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPDeviceKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SPPDeviceKit", targets: ["SPPDeviceKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore"),
        .package(path: "../SPPIPCModels")
    ],
    targets: [
        .target(
            name: "SPPDeviceKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPIPCModels", package: "SPPIPCModels")
            ],
            path: "Sources/SPPDeviceKit"
        )
    ]
)
