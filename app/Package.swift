// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Loft",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Loft", targets: ["Loft"]),
    ],
    targets: [
        .target(name: "LoftKit"),
        .executableTarget(
            name: "Loft",
            dependencies: ["LoftKit"]
        ),
        .testTarget(
            name: "LoftKitTests",
            dependencies: ["LoftKit"]
        ),
    ]
)
