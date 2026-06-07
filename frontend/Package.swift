// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CCMimoRescueUI",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "CCMimoRescueUI", targets: ["CCMimoRescueUI"])
    ],
    targets: [
        .executableTarget(
            name: "CCMimoRescueUI",
            path: "Sources/CCMimoRescueUI"
        )
    ]
)
