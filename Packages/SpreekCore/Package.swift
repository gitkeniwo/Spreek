// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpreekCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SpreekCore", targets: ["SpreekCore"]),
    ],
    targets: [
        .target(name: "SpreekCore"),
        .testTarget(name: "SpreekCoreTests", dependencies: ["SpreekCore"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
