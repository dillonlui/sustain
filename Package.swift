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
    targets: [
        .executableTarget(name: "Sustain"),
        .testTarget(
            name: "SustainTests",
            dependencies: ["Sustain"]
        )
    ]
)
