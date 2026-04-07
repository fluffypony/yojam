// NOTE: This Package.swift is for source organization, dependency resolution,
// and `swift test` only. The canonical build artifact is the Xcode project.
// Run `xcodegen generate` to produce Yojam.xcodeproj.
// The SPM executable target does NOT produce a proper .app bundle with
// Info.plist, entitlements, or URL scheme registration.

// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Yojam",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yojam", targets: ["Yojam"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "Yojam",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Yojam",
            exclude: ["Resources/Info.plist", "Resources/Yojam.entitlements", "Resources/menubar.svg"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "YojamTests",
            dependencies: ["Yojam"],
            path: "Tests/YojamTests"
        )
    ]
)
