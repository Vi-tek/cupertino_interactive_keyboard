// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "cupertino_interactive_keyboard",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "cupertino-interactive-keyboard", targets: ["cupertino_interactive_keyboard"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "cupertino_interactive_keyboard",
            dependencies: [
                .product(
                    name: "FlutterFramework",
                    package: "FlutterFramework"
                )
            ],
            resources: []
        )
    ]
)
