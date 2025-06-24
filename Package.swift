// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NudgeServer",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.9.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.8.0")
    ],
    targets: [
        .executableTarget(
            name: "NudgeServer",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle")
            ],
            path: "Sources/ServerSrc",
        ),
        .testTarget(
            name: "NudgeTests",
            dependencies: ["NudgeServer"],
            path: "Tests/CLIToolTests"
        )
    ]
) 
