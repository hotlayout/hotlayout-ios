// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HotLayout",
    platforms: [
        // iOS is the target platform. macOS is declared so that the rules, the shared case
        // tables and the off-screen drawing tests run with `swift test`; it is not a product
        // platform of the package.
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(name: "HotLayout", targets: ["HotLayout"]),
    ],
    targets: [
        .target(
            name: "HotLayout",
            resources: [
                .copy("Resources/icons.json"),
                .copy("Resources/built-in-theme.json"),
            ]
        ),
        .testTarget(
            name: "HotLayoutTests",
            dependencies: ["HotLayout"],
            resources: [
                .copy("Resources/contract"),
            ]
        ),
        // Compiles the README example with `import HotLayout` alone: the public API is enough.
        .testTarget(
            name: "HotLayoutAPITests",
            dependencies: ["HotLayout"]
        ),
    ]
)
