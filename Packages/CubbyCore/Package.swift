// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CubbyCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "CubbyCore", targets: ["CubbyCore"]),
    ],
    targets: [
        .target(name: "CubbyCore"),
        .testTarget(name: "CubbyCoreTests", dependencies: ["CubbyCore"]),
    ],
    swiftLanguageModes: [.v5]
)
