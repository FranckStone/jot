// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jot",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Jot", targets: ["Jot"])],
    targets: [
        .target(name: "JotCore"),
        .executableTarget(name: "Jot", dependencies: ["JotCore"]),
        .testTarget(name: "JotCoreTests", dependencies: ["JotCore"])
    ]
)
