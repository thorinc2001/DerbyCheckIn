// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DerbyCheckIn",
    platforms: [.macOS(.v14)],
    targets: [
        // Racers, groups, check-in rules and GPRM rosters. Foundation only, no screens.
        .target(name: "DerbyCore"),
        // What both apps share on the Mac: the Store (saving, folders, photos), import and
        // export panels, and the Settings window.
        .target(name: "DerbyKit", dependencies: ["DerbyCore"]),
        .executableTarget(name: "DerbyCheckIn", dependencies: ["DerbyCore", "DerbyKit"]),
        // The Web folder is copied into the app bundle by build.sh.
        .executableTarget(name: "DerbyWebCheckIn", dependencies: ["DerbyCore", "DerbyKit"], exclude: ["Web"]),
        .testTarget(name: "DerbyCoreTests", dependencies: ["DerbyCore"]),
        .testTarget(name: "DerbyKitTests", dependencies: ["DerbyCore", "DerbyKit"]),
        .testTarget(name: "DerbyCheckInTests", dependencies: ["DerbyCheckIn"]),
    ]
)
