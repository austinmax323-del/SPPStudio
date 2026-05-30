// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPExportKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SPPExportKit", targets: ["SPPExportKit"])
    ],
    dependencies: [
        .package(path: "../SPPCore"),
        .package(path: "../SPPHookKit"),
        .package(path: "../SPPTheosKit"),
        .package(path: "../SPPUIBuilderKit")
    ],
    targets: [
        .target(
            name: "SPPExportKit",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPHookKit", package: "SPPHookKit"),
                .product(name: "SPPTheosKit", package: "SPPTheosKit"),
                .product(name: "SPPUIBuilderKit", package: "SPPUIBuilderKit")
            ],
            path: "Sources/SPPExportKit"
        )
    ]
)
