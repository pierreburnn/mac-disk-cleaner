// swift-tools-version:5.9
import PackageDescription

// The SwiftUI app only builds on macOS; the core library and its tests are
// portable Foundation code (handy for quick checks on Linux).
var products: [Product] = [.library(name: "DiskCleanerCore", targets: ["DiskCleanerCore"])]
var targets: [Target] = [
    .target(name: "DiskCleanerCore"),
    .testTarget(name: "DiskCleanerCoreTests", dependencies: ["DiskCleanerCore"]),
]
#if os(macOS)
products.append(.executable(name: "DiskCleaner", targets: ["DiskCleaner"]))
targets.append(.executableTarget(name: "DiskCleaner", dependencies: ["DiskCleanerCore"]))
#endif

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v13)],
    products: products,
    targets: targets,
    swiftLanguageVersions: [.v5]
)
