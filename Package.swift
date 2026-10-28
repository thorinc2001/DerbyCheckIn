// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DerbyCheckIn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "DerbyCheckIn", path: "Sources/DerbyCheckIn"),
        // Shares Models, Store, CSV and the Settings views with DerbyCheckIn through
        // symlinks in Sources/DerbyWebCheckIn/Shared. The Web folder is copied into the app bundle.
        .executableTarget(name: "DerbyWebCheckIn", path: "Sources/DerbyWebCheckIn", exclude: ["Web"]),
    ]
)
