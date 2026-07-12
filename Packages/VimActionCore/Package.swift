// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VimActionCore",
    products: [
        .library(name: "VimEngine", targets: ["VimEngine"]),
    ],
    targets: [
        .target(name: "VimEngine"),
        .testTarget(name: "VimEngineTests", dependencies: ["VimEngine"]),
    ]
)
