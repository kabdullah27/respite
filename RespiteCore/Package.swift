// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RespiteCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RespiteCore", targets: ["RespiteCore"])
    ],
    targets: [
        .target(name: "RespiteCore"),
        .testTarget(name: "RespiteCoreTests", dependencies: ["RespiteCore"])
    ]
)
