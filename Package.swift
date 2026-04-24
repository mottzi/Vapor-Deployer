// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Vapor-Deployer",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.4.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.12.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
        .package(url: "https://github.com/mottzi/Vapor-Mist.git", from: "0.19.0"),
        .package(url: "https://github.com/elementary-swift/elementary.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "deployer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Leaf", package: "leaf"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "Mist", package: "Vapor-Mist"),
                .product(name: "Elementary", package: "elementary"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
//        .testTarget(
//            name: "DeployerTests",
//            dependencies: [
//                .target(name: "deployer"),
//            ]
//        ),
    ],
    swiftLanguageModes: [
        .v6
    ]
)
