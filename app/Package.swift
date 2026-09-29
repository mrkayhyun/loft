// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Burrow",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Burrow", targets: ["Burrow"]),
    ],
    targets: [
        .target(name: "BurrowKit"),
        .executableTarget(
            name: "Burrow",
            dependencies: ["BurrowKit"]
        ),
        .testTarget(
            name: "BurrowKitTests",
            dependencies: ["BurrowKit"]
        ),
    ]
)
