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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.3")
    ],
    targets: [
        .executableTarget(
            name: "CCMimoRescueUI",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/CCMimoRescueUI"
        )
    ]
)
