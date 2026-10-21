// swift-tools-version: 6.2
// Luna is built with SwiftPM only (no Xcode project): `make run` assembles Luna.app from this package.
import PackageDescription

let package = Package(
    name: "Luna",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Luna", targets: ["Luna"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0")
    ],
    targets: [
        // Private macOS display APIs, resolved at runtime with dlsym so a missing symbol degrades a feature
        // instead of crashing the app. Nothing private is linked.
        .target(
            name: "CPrivate",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        // Displays, hardware control and the brightness logic. No UI.
        .target(
            name: "LunaCore",
            dependencies: ["CPrivate"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("CoreAudio"),
            ]
        ),
        // The app: menu bar panel, settings, keys, updates.
        .executableTarget(
            name: "Luna",
            dependencies: [
                "LunaCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "LunaCoreTests",
            dependencies: ["LunaCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
