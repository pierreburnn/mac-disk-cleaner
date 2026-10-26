// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DiskCleaner",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DiskCleanerCore", targets: ["DiskCleanerCore"]),
        .executable(name: "DiskCleaner", targets: ["DiskCleaner"])
    ],
    targets: [
        .target(
            name: "DiskCleanerCore"
        ),
        .executableTarget(
            name: "DiskCleaner",
            dependencies: ["DiskCleanerCore"]
        ),
        .testTarget(
            name: "DiskCleanerCoreTests",
            dependencies: ["DiskCleanerCore"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
