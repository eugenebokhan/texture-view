// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "TextureView",
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
            url: "https://github.com/eugenebokhan/metal-tools.git",
            .upToNextMajor(from: "1.0.0")
        ),
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
