// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AgentLight",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentLightCore", targets: ["AgentLightCore"]),
        .executable(name: "agent-light", targets: ["AgentLightCLI"]),
        .executable(name: "AgentLight", targets: ["AgentLightApp"]),
    ],
    targets: [
        .target(name: "AgentLightCore"),
        .target(
            name: "AgentLightHID",
            dependencies: ["AgentLightCore"],
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("IOKit"),
            ]
        ),
        .executableTarget(
            name: "AgentLightCLI",
            dependencies: ["AgentLightCore", "AgentLightHID"]
        ),
        .executableTarget(
            name: "AgentLightApp",
            dependencies: ["AgentLightCore", "AgentLightHID"]
        ),
        .testTarget(name: "AgentLightCoreTests", dependencies: ["AgentLightCore"]),
        .testTarget(name: "AgentLightHIDTests", dependencies: ["AgentLightHID"]),
    ]
)
