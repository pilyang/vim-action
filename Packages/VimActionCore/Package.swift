// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VimActionCore",
    products: [
        .library(name: "VimEngine", targets: ["VimEngine"]),
        .library(name: "VimActionConfig", targets: ["VimActionConfig"]),
    ],
    dependencies: [
        // 설정 파서 전용 의존. VimEngine은 의존을 선언하지 않아 Yams가 엔진으로 새지 않는다.
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0")
    ],
    targets: [
        .target(name: "VimEngine"),
        .testTarget(name: "VimEngineTests", dependencies: ["VimEngine"]),
        .target(
            name: "VimActionConfig",
            dependencies: ["VimEngine", .product(name: "Yams", package: "Yams")]
        ),
        .testTarget(name: "VimActionConfigTests", dependencies: ["VimActionConfig"]),
    ]
)
