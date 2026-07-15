// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "NuphyBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AgentLightCore", targets: ["AgentLightCore"]),
        .executable(name: "agent-light", targets: ["AgentLightCLI"]),
        .executable(name: "NuphyBar", targets: ["AgentLightApp"]),
    ],
    targets: [
        .target(
            name: "CDarwinNotify",
            publicHeadersPath: "include"
        ),
        .target(name: "AgentLightCore", dependencies: ["CDarwinNotify"]),
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
            dependencies: ["AgentLightCore", "AgentLightHID"],
            exclude: ["Resources"],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        ),
        .testTarget(
            name: "AgentLightAppTests",
            dependencies: ["AgentLightApp", "AgentLightCore"]
        ),
        .testTarget(name: "AgentLightCoreTests", dependencies: ["AgentLightCore"]),
        .testTarget(name: "AgentLightHIDTests", dependencies: ["AgentLightHID"]),
    ]
)
