// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MTGSheetOptimizer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MTGSheetOptimizer"),
        .testTarget(name: "MTGSheetOptimizerTests", dependencies: ["MTGSheetOptimizer"]),
    ]
)
