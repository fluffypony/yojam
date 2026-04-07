// NOTE: This Package.swift is for source organization, dependency resolution,
// and `swift test` only. The canonical build artifact — with .appex bundles
// for the Share Extension and Safari Web Extension, the native messaging host
// binary, and proper entitlements — is produced by `xcodegen generate && xcodebuild`.
//
// `swift build` produces only the bare Yojam executable and YojamCore library.
// It does NOT produce a working .app bundle with Info.plist, entitlements,
// URL scheme registration, or embedded extensions.

// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Yojam",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "YojamCore", targets: ["YojamCore"]),
        .executable(name: "Yojam", targets: ["Yojam"]),
        .executable(name: "yojam-cli", targets: ["YojamCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .target(
            name: "YojamCore",
            path: "Sources/YojamCore"
        ),
        .executableTarget(
            name: "Yojam",
            dependencies: [
                "YojamCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Yojam",
            exclude: ["Resources/Info.plist", "Resources/Yojam.entitlements", "Resources/menubar.svg"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "YojamCLI",
            dependencies: ["YojamCore"],
            path: "Sources/YojamCLI",
            exclude: ["YojamCLI.entitlements"]
        ),
        .testTarget(
            name: "YojamTests",
            dependencies: ["Yojam"],
            path: "Tests/YojamTests"
        ),
        .testTarget(
            name: "YojamCoreTests",
            dependencies: ["YojamCore"],
            path: "Tests/YojamCoreTests"
        )
    ]
)
