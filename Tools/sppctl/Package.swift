// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "sppctl",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "sppctl", targets: ["sppctl"]),
        .executable(name: "jarvis", targets: ["jarvis"]),
        .executable(name: "openjarvis-checks", targets: ["OpenJarvisChecks"]),
    ],
    dependencies: [
        .package(path: "../../Packages/SPPCore"),
        .package(path: "../../Packages/SPPHookKit"),
        .package(path: "../../Packages/SPPTheosKit"),
        .package(path: "../../Packages/SPPExportKit"),
        .package(path: "../../Packages/SPPDeviceKit"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .target(
            name: "OpenJarvisCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/OpenJarvisCore"
        ),
        .executableTarget(
            name: "sppctl",
            dependencies: [
                .product(name: "SPPCore", package: "SPPCore"),
                .product(name: "SPPHookKit", package: "SPPHookKit"),
                .product(name: "SPPTheosKit", package: "SPPTheosKit"),
                .product(name: "SPPExportKit", package: "SPPExportKit"),
                .product(name: "SPPDeviceKit", package: "SPPDeviceKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/sppctl"
        ),
        .executableTarget(
            name: "jarvis",
            dependencies: [
                "OpenJarvisCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/jarvis"
        ),
        .executableTarget(
            name: "OpenJarvisChecks",
            dependencies: [
                "OpenJarvisCore"
            ],
            path: "Sources/OpenJarvisChecks"
        )
    ]
)
