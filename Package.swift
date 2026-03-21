// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "virt",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "virt",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            linkerSettings: [
                .linkedFramework("Virtualization"),
            ]
        ),
        .testTarget(
            name: "virtTests",
            dependencies: ["virt"]
        ),
    ]
)
