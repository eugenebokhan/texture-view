// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "texture-view",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "TextureView",
            targets: ["TextureView"]
        ),
    ], dependencies: [
        .package(
            url: "https://github.com/computer-graphics-tools/metal-tools.git",
            .upToNextMajor(from: "1.3.0")
        )
    ],
    targets: [
        .target(
            name: "TextureView",
            dependencies: [
                .product(
                    name: "MetalTools",
                    package: "metal-tools"
                ),
            ],
            resources: [.process("Shaders/Shaders.metal")]
        )
    ]
)
