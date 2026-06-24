// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SendrealmIOS",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "SendrealmIOS",
            targets: ["SendrealmIOS"]
        )
    ],
    targets: [
        .target(
            name: "SendrealmIOS",
            path: "Sources/SendrealmIOS"
        ),
        .testTarget(
            name: "SendrealmIOSTests",
            dependencies: ["SendrealmIOS"],
            path: "Tests/SendrealmIOSTests"
        )
    ]
)
