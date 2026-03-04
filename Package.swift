// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Deployer",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "Deployer", targets: ["Deployer"])
    ],
    dependencies: [
        .package(url: "https://github.com/mottzi/Vapor-Mist.git", from: "0.15.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.8.0"),
    ],
    targets: [
        .target(
            name: "Deployer",
            dependencies: [
                .product(name: "Mist", package: "Vapor-Mist"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
