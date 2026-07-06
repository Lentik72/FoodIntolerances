// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HealthGraphCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "HealthGraphCore", targets: ["HealthGraphCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "HealthGraphCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HealthGraphCoreTests",
            dependencies: [
                "HealthGraphCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
