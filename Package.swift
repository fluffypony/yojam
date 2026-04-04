// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "Yojam",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Yojam", targets: ["Yojam"])
    ],
    targets: [
        .executableTarget(
            name: "Yojam",
            path: "Sources/Yojam",
            exclude: ["Resources/Info.plist", "Resources/Yojam.entitlements"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "YojamTests",
            dependencies: ["Yojam"],
            path: "Tests/YojamTests"
        )
    ]
)
