// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPSimulatorHost",
    platforms: [.macOS(.v14), .iOS(.v16)],
    dependencies: [
        .package(path: "../../Packages/SPPCore"),
        .package(path: "../../Packages/SPPIPCModels"),
        .package(path: "../../Packages/SPPRuntimeKit"),
        .package(path: "../../Packages/SPPUIBuilderKit")
    ],
    targets: [
        .executableTarget(
            name: "SPPSimulatorHost",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPIPCModels", package: "SPPIPCModels"),
                .product(name: "SPPRuntimeKit", package: "SPPRuntimeKit"),
                .product(name: "SPPUIBuilderKit", package: "SPPUIBuilderKit")
            ],
            path: "Sources"
        )
    ]
)
