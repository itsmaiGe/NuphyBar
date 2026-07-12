// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AgentLight",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentLightCore", targets: ["AgentLightCore"]),
    ],
    targets: [
        .target(name: "AgentLightCore"),
        .testTarget(name: "AgentLightCoreTests", dependencies: ["AgentLightCore"]),
    ]
)

