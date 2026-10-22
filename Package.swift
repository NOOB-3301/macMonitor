// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "macmon",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CShims",
            publicHeadersPath: "include",
            cSettings: [.unsafeFlags(["-Os"])]
        ),
        .target(
            name: "MacmonCore",
            dependencies: ["CShims"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MacmonApp",
            dependencies: ["MacmonCore", "CShims"],
            path: "Sources/MacmonApp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
