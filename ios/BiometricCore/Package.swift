// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BiometricCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "BiometricCore", targets: ["BiometricCore"])
    ],
    targets: [
        .target(name: "BiometricCore"),
        .testTarget(name: "BiometricCoreTests", dependencies: ["BiometricCore"])
    ]
)
