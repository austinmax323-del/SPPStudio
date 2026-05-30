// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftPlaygroundPlusPlusStudio",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/SPPCore"),
        .package(path: "../../Packages/SPPIPCModels"),
        .package(path: "../../Packages/SPPSymbolKit"),
        .package(path: "../../Packages/SPPRuntimeKit"),
        .package(path: "../../Packages/SPPHookKit"),
        .package(path: "../../Packages/SPPTheosKit"),
        .package(path: "../../Packages/SPPExportKit"),
        .package(path: "../../Packages/SPPUIBuilderKit"),
        .package(path: "../../Packages/SPPInstrumentationBridge"),
        .package(path: "../../Packages/SPPDeviceKit"),
        .package(path: "../../Packages/SPPSourceIndexKit")
    ],
    targets: [
        .executableTarget(
            name: "SwiftPlaygroundPlusPlusStudio",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPIPCModels", package: "SPPIPCModels"),
                .product(name: "SPPSymbolKit", package: "SPPSymbolKit"),
                .product(name: "SPPRuntimeKit", package: "SPPRuntimeKit"),
                .product(name: "SPPHookKit", package: "SPPHookKit"),
                .product(name: "SPPTheosKit", package: "SPPTheosKit"),
                .product(name: "SPPExportKit", package: "SPPExportKit"),
                .product(name: "SPPUIBuilderKit", package: "SPPUIBuilderKit"),
                .product(name: "SPPInstrumentationBridge", package: "SPPInstrumentationBridge"),
                .product(name: "SPPDeviceKit", package: "SPPDeviceKit"),
                .product(name: "SPPSourceIndexKit", package: "SPPSourceIndexKit")
            ],
            path: "Sources"
        )
    ]
)
