// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SPPInstrumentationBridge",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: [
        .library(name: "SPPInstrumentationBridge", targets: ["SPPInstrumentationBridge"])
    ],
    dependencies: [
        .package(path: "../SPPCore"),
        .package(path: "../SPPRuntimeKit"),
        .package(path: "../SPPSymbolKit")
    ],
    targets: [
        .target(
            name: "SPPInstrumentationBridge",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPRuntimeKit", package: "SPPRuntimeKit"),
                .product(name: "SPPSymbolKit", package: "SPPSymbolKit")
            ],
            path: "Sources/SPPInstrumentationBridge"
        )
    ]
)
