// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NudgeServer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NudgeLibrary", targets: ["NudgeLibrary"]),
        .executable(name: "NudgeServer", targets: ["NudgeServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.8.0")
    ],
    targets: [
        .target(
            name: "NudgeLibrary",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/NudgeLibrary"
        ),
        .executableTarget(
            name: "NudgeServer",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                "NudgeLibrary"
            ],
            path: "Sources/NudgeServer",
        ),
        .testTarget(
            name: "NudgeTests",
            dependencies: ["NudgeLibrary"],
            path: "Tests/NudgeServerTests"
        )
    ]
) 
