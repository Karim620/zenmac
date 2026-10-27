// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ZenMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ZenMac", targets: ["ZenMac"])
    ],
    targets: [
        .executableTarget(
            name: "ZenMac",
            path: "ZenMac"
        )
    ]
)
