// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CubbyEval",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(path: "../../Packages/CubbyCore"),
    ],
    targets: [
        .executableTarget(
            name: "cubby-eval",
            dependencies: [
                .product(name: "CubbyCore", package: "CubbyCore"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
