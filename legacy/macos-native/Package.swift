// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "KaiMD",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "KaiMD", targets: ["KaiMD"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-markdown.git",
            exact: "0.8.0"
        ),
        .package(
            url: "https://github.com/swiftlang/swift-testing.git",
            exact: "0.9.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "KaiMD",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("UniformTypeIdentifiers"),
            ]
        ),
        .testTarget(
            name: "KaiMDTests",
            dependencies: [
                "KaiMD",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
