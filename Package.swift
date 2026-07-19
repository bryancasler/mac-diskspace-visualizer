// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "DiskVis",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DiskVis",
            path: "Sources/DiskVis"
        )
    ]
)
