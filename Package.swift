// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sustain",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sustain", targets: ["Sustain"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .executableTarget(
            name: "Sustain",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "SustainTests",
            dependencies: ["Sustain"]
        )
    ]
)
