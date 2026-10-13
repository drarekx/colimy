// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Colimy",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Colimy",
            path: "Sources/Colimy"
        )
    ]
)
