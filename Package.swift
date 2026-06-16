// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NutritionKit",
    platforms: [
        .iOS(.v26),
    ],
    products: [
        .library(
            name: "NutritionKit",
            targets: ["NutritionKit"]),
    ],
    targets: [
        .target(
            name: "NutritionKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]),
        .testTarget(
            name: "NutritionKitTests",
            dependencies: ["NutritionKit"],
            resources: [
                .process("TestAssets.xcassets")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
