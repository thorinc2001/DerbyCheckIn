import AppKit
import DerbyCore
import Testing
@testable import DerbyKit

/// A fresh folder for each test, so nothing touches the real event.
func tempFolder(_ name: String = "store") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("DerbyKitTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name, isDirectory: true)
}

let orange = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { rect in
    NSColor.orange.setFill(); rect.fill(); return true
}

@MainActor
@Suite("Store")
struct StoreTests {
    @Test func editsThroughTheBindingFollowTheRules() throws {
        let store = Store(folder: tempFolder())
        store.addRacer(rank: "CS_3_Bears")
        let id = try #require(store.selection)
        store.binding(id).wrappedValue.weightOz = 4.9
        store.binding(id).wrappedValue.carName = "A very long car name indeed"
        let racer = store.data.racers[0]
        #expect(racer.carNumber == 400 && racer.subgroup == "Bears")
        #expect(racer.inspection.weightOK)
        #expect(racer.carName.count == 20)
    }

    @Test func savesAndReloads() {
        let folder = tempFolder()
        let store = Store(folder: folder)
        store.addRacer(rank: "Outlaw")
        store.data.racers[0].firstName = "Robin"
        store.save()
        #expect(Store(folder: folder).data.racers.first?.firstName == "Robin")
    }

    @Test func oldEventFilesGetStartNumbers() throws {
        let folder = tempFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let old = #"{"eventName":"x","groups":[{"rank":"CS_3_Bears","subgroup":"Bears"}],"maxWeightOz":5,"imageFolderOnPC":"","racers":[]}"#
        try old.write(to: folder.appendingPathComponent("event.json"), atomically: true, encoding: .utf8)
        let store = Store(folder: folder)
        #expect(store.message == nil)
        #expect(store.data.groups.first?.startNumber == 400)
    }

    @Test func unreadableEventIsKeptAside() throws {
        let folder = tempFolder()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "not json".write(to: folder.appendingPathComponent("event.json"), atomically: true, encoding: .utf8)
        let store = Store(folder: folder)
        #expect(store.message?.contains("could not be read") == true)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.hasPrefix("event-unreadable-") })
    }

    @Test func photosAreSavedReplacedAndRemoved() throws {
        let store = Store(folder: tempFolder())
        store.addRacer()
        let id = try #require(store.selection)
        store.setPhoto(orange, kind: .car, racerID: id)
        let first = try #require(store.data.racers[0].carPhoto)
        #expect(FileManager.default.fileExists(atPath: store.photoURL(first).path))
        store.setPhoto(nil, kind: .car, racerID: id)
        #expect(store.data.racers[0].carPhoto == nil)
        #expect(!FileManager.default.fileExists(atPath: store.photoURL(first).path))
    }

    @Test func exportWritesTheRosterAndPhotos() throws {
        let store = Store(folder: tempFolder())
        store.data.imageFolderOnPC = #"C:\GPRM\Images"#
        _ = store.data.importRoster(text: "First Name,Last Name,Car#,Car Name,Rank,Subgroup\r\nAlex,Avery,405,Comet,CS_3_Bears,Bears\r\nBlair,Brooks,1003,,GS_4th_1422,GS_4th_1422\r\n")
        let alex = try #require(store.data.racers.first { $0.carNumber == 405 })
        store.setPhoto(orange, kind: .car, racerID: alex.id)
        let dir = try store.writeExport(store.data.racers, into: tempFolder("export"))
        let csv = try String(contentsOf: dir.appendingPathComponent("GPRM Roster.csv"), encoding: .utf8)
        #expect(csv.contains(#"Alex,Avery,405,Comet,CS_3_Bears,Bears,False,False,False,False,False,C:\GPRM\Images\405.jpg"#))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Images/405.jpg").path))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Car Photos/405.jpg").path))
    }

    @Test func deletingARacerRemovesTheirPhotos() throws {
        let store = Store(folder: tempFolder())
        store.addRacer()
        let id = try #require(store.selection)
        store.setPhoto(orange, kind: .racer, racerID: id)
        let file = try #require(store.data.racers[0].racerPhoto)
        store.deleteRacer(id)
        #expect(store.data.racers.isEmpty && store.selection == nil)
        #expect(!FileManager.default.fileExists(atPath: store.photoURL(file).path))
    }
}

@MainActor
@Suite("Storage folders")
struct StorageTests {
    @Test func findsOneDriveAndGoogleDrive() throws {
        let home = tempFolder("home")
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: storage.appendingPathComponent("OneDrive-Personal"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: storage.appendingPathComponent("GoogleDrive-pack@example.com/My Drive"), withIntermediateDirectories: true)
        let clouds = CloudFolder.detect(home: home)
        #expect(clouds.map(\.name) == ["Google Drive (pack@example.com)", "OneDrive – Personal"])
        #expect(clouds.first?.url.lastPathComponent == "My Drive")
        #expect(CloudFolder.service(of: clouds[1].url.appendingPathComponent("Derby Check-In"), in: clouds)?.service == .oneDrive)
    }

    @Test func movingBringsTheEventAndPhotos() throws {
        let local = tempFolder("local")
        let store = Store(folder: local)
        store.addRacer(rank: "CS_3_Bears")
        store.data.racers[0].firstName = "Jordan"
        store.setPhoto(orange, kind: .car, racerID: store.data.racers[0].id)
        store.save()

        let cloud = tempFolder("cloud")
        #expect(Store.event(in: cloud) == nil)
        store.useDataFolder(cloud, bringCurrentEvent: true)
        #expect(store.folder.standardizedFileURL == cloud.standardizedFileURL)
        #expect(Store.event(in: cloud)?.racers.first?.firstName == "Jordan")
        let photo = try #require(store.data.racers[0].carPhoto)
        #expect(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("Photos/\(photo)").path))
        #expect(Store.event(in: local)?.racers.count == 1, "the old folder is kept as a backup")

        store.data.racers[0].carName = "Aura"
        store.save()
        #expect(Store.event(in: cloud)?.racers.first?.carName == "Aura")
        #expect(Store.event(in: local)?.racers.first?.carName == "")
    }

    @Test func openingAnExistingEventLoadsIt() throws {
        let shared = tempFolder("shared")
        let first = Store(folder: shared)
        first.addRacer(rank: "Outlaw")
        first.data.racers[0].firstName = "Robin"
        first.setPhoto(orange, kind: .car, racerID: first.data.racers[0].id)
        first.save()

        let second = Store(folder: tempFolder("other-mac"))
        second.addRacer()
        second.useDataFolder(shared, bringCurrentEvent: false)
        #expect(second.data.racers.map(\.firstName) == ["Robin"])
        let photo = try #require(second.data.racers[0].carPhoto)
        #expect(FileManager.default.fileExists(atPath: second.photoURL(photo).path))
    }

    @Test func testStoresLeaveTheSavedFolderAlone() {
        let before = UserDefaults.standard.string(forKey: "dataFolder")
        let store = Store(folder: tempFolder())
        store.useDataFolder(tempFolder("elsewhere"), bringCurrentEvent: true)
        #expect(UserDefaults.standard.string(forKey: "dataFolder") == before)
    }
}
