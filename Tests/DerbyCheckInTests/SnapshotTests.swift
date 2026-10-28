import AppKit
import DerbyCore
import SwiftUI
import Testing
@testable import DerbyCheckIn
@testable import DerbyKit

/// Draws the racer form and each Settings tab, light and dark, to PNG files so the layout can
/// be checked without the screen. Off unless DERBY_SNAPSHOTS names a folder:
///   DERBY_SNAPSHOTS=/tmp/derby-shots swift test --filter Snapshots
/// It draws the view hierarchy (no Screen Recording permission needed), so the window looks
/// inactive: switches and accents are grey.
@MainActor
@Suite("Snapshots", .serialized, .enabled(if: ProcessInfo.processInfo.environment["DERBY_SNAPSHOTS"] != nil))
struct SnapshotTests {
    let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DERBY_SNAPSHOTS"] ?? "/tmp")

    func sampleStore() throws -> Store {
        let store = Store(folder: FileManager.default.temporaryDirectory.appendingPathComponent("derby-snapshots-\(UUID())"))
        let roster = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Fixtures/sample-roster.csv")
        _ = store.data.importRoster(text: try String(contentsOf: roster, encoding: .utf8))
        return store
    }

    /// Hosts `view` in an offscreen window `width` points wide, as tall as its content.
    func shot<V: View>(_ view: V, _ name: String, width: CGFloat) async throws {
        _ = NSApplication.shared
        for dark in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 1400),
                                  styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: view)
            window.contentView = host
            window.orderFrontRegardless()
            try await Task.sleep(for: .seconds(1))
            let height = min(max(host.fittingSize.height, 100), 1400)
            window.setContentSize(NSSize(width: width, height: height))
            try await Task.sleep(for: .seconds(0.5))
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: folder.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            window.orderOut(nil)
        }
    }

    @Test func racerForm() async throws {
        let store = try sampleStore()
        let id = try #require(store.data.racers.first { $0.carNumber == 405 }?.id)
        store.binding(id).wrappedValue.weightOz = 4.9
        try await shot(RacerDetailView(racer: store.binding(id)).environmentObject(store), "racer", width: 680)
    }

    @Test func settingsTabs() async throws {
        let store = try sampleStore()
        try await shot(GeneralSettings().environmentObject(store), "settings-general", width: 520)
        try await shot(GroupsView().environmentObject(store), "settings-groups", width: 720)
        try await shot(StorageSettings().environmentObject(store), "settings-storage", width: 600)
    }
}
