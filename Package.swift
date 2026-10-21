// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StorageCleaner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "StorageCleaner", targets: ["StorageCleaner"]),
        .library(name: "StorageCleanerCore", targets: ["StorageCleanerCore"]),
        .executable(name: "StorageCleanerTests", targets: ["StorageCleanerTests"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "StorageCleanerCore",
            dependencies: [],
            path: "Sources/StorageCleanerCore"
        ),
        .executableTarget(
            name: "StorageCleaner",
            dependencies: ["StorageCleanerCore"],
            path: "Sources/StorageCleaner"
        ),
        .executableTarget(
            name: "StorageCleanerTests",
            dependencies: ["StorageCleanerCore"],
            path: "Tests/StorageCleanerTests"
        )
    ]
)
