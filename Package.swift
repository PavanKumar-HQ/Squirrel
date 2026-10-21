// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Squirrel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Squirrel", targets: ["Squirrel"]),
        .library(name: "SquirrelCore", targets: ["SquirrelCore"]),
        .executable(name: "SquirrelTests", targets: ["SquirrelTests"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SquirrelCore",
            dependencies: [],
            path: "Sources/SquirrelCore"
        ),
        .executableTarget(
            name: "Squirrel",
            dependencies: ["SquirrelCore"],
            path: "Sources/Squirrel",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "SquirrelTests",
            dependencies: ["SquirrelCore"],
            path: "Tests/SquirrelTests"
        )
    ]
)
