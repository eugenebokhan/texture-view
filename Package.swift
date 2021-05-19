// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "TextureView",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "TextureView",
                 targets: ["TextureView"]),
    ], dependencies: [
        .package(name: "Alloy",
                 url: "https://github.com/s1ddok/Alloy.git",
                 .upToNextMajor(from: "0.17.0"))
    ],
    targets: [
        .target(name: "TextureView",
                dependencies: ["Alloy"],
                resources: [.process("Shaders/Shaders.metal")])
    ]
)
