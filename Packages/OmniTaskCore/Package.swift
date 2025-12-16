// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OmniTaskCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "OmniTaskCore",
            targets: ["OmniTaskCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "OmniTaskCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "OmniTaskCoreTests",
            dependencies: ["OmniTaskCore"]
        )
    ]
)
