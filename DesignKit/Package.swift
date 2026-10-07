// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DesignKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DesignKit", targets: ["DesignKit"])
    ],
    targets: [
        .target(name: "DesignKit")
    ]
)
