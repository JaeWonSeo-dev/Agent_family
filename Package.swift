// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentFamily",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AgentFamily", targets: ["AgentFamily"])
    ],
    targets: [
        .executableTarget(
            name: "AgentFamily",
            path: "src"
        )
    ]
)
