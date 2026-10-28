// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DerbyCheckIn",
    platforms: [.macOS(.v14)],
    targets: [
        // Racers, groups, check-in rules and GPRM rosters. Foundation only, no screens.
        .target(name: "DerbyCore"),
        .executableTarget(name: "DerbyCheckIn", dependencies: ["DerbyCore"], path: "Sources/DerbyCheckIn"),
        // Shares Store, Export and the Settings views with DerbyCheckIn through
        // symlinks in Sources/DerbyWebCheckIn/Shared. The Web folder is copied into the app bundle.
        .executableTarget(name: "DerbyWebCheckIn", dependencies: ["DerbyCore"], path: "Sources/DerbyWebCheckIn", exclude: ["Web"]),
    ]
)
