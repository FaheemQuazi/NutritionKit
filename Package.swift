// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "NutritionKit",
    defaultLocalization: "en",
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
            resources: [
                .process("Resources"),
                .copy("PrivacyInfo.xcprivacy"),
            ],
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
