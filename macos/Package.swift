// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BTSentinelMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "BTSentinelMac", targets: ["BTSentinelMac"])
    ],
    targets: [
        .executableTarget(
            name: "BTSentinelMac",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
