// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaroldKit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "HaroldKit", targets: ["HaroldKit"])
    ],
    targets: [
        .target(name: "HaroldKit"),
        .testTarget(name: "HaroldKitTests", dependencies: ["HaroldKit"]),
    ]
)
