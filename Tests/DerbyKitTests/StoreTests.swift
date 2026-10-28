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

    @Test func photosAreSavedAndReplaced() throws {
        let store = Store(folder: tempFolder())
        store.addRacer()
        let id = try #require(store.selection)
        store.setPhoto(orange, kind: .car, racerID: id)
        let first = try #require(store.data.racers[0].carPhoto)
        #expect(FileManager.default.fileExists(atPath: store.photoURL(first).path))
        store.setPhoto(orange, kind: .car, racerID: id)
        #expect(store.data.racers[0].carPhoto != first, "a new file name each time")
        store.setPhoto(nil, kind: .car, racerID: id)
        #expect(store.data.racers[0].carPhoto == nil)
        #expect(FileManager.default.fileExists(atPath: store.photoURL(first).path), "kept so Undo can put it back")
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

    @Test func deletingARacerClearsTheSelection() throws {
        let store = Store(folder: tempFolder())
        store.addRacer()
        let id = try #require(store.selection)
        store.deleteRacer(id)
        #expect(store.data.racers.isEmpty && store.selection == nil)
    }

    @Test func unusedPhotosAreRemovedAtLaunchOnlyWhenADayOld() throws {
        let folder = tempFolder()
        let store = Store(folder: folder)
        store.addRacer()
        let id = try #require(store.selection)
        store.setPhoto(orange, kind: .car, racerID: id)
        let used = try #require(store.data.racers[0].carPhoto)
        store.setPhoto(orange, kind: .racer, racerID: id)
        store.setPhoto(nil, kind: .racer, racerID: id)
        store.save()
        let fm = FileManager.default
        let photos = try fm.contentsOfDirectory(atPath: store.photosFolder.path)
        let unused = try #require(photos.first { $0 != used })
        _ = Store(folder: folder)
        #expect(fm.fileExists(atPath: store.photoURL(unused).path), "too new: it may belong to an event still syncing")

        let twoDaysAgo = Date().addingTimeInterval(-2 * 24 * 60 * 60)
        for name in photos { try fm.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: store.photoURL(name).path) }
        _ = Store(folder: folder)
        #expect(!fm.fileExists(atPath: store.photoURL(unused).path))
        #expect(fm.fileExists(atPath: store.photoURL(used).path), "photos a racer uses are kept")
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

@MainActor
@Suite("Undo")
struct UndoTests {
    /// A store with an undo manager that groups by event, as the app's window does: each
    /// `step` is one click or key press, after which the run loop closes the undo group.
    func makeStore() -> (Store, UndoManager) {
        let store = Store(folder: tempFolder())
        let undo = UndoManager()
        store.undoManager = undo
        return (store, undo)
    }

    func step(_ undo: UndoManager, _ action: () -> Void) {
        action()
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }

    @Test func undoAndRedoADeletedRacerWithPhotos() throws {
        let (store, undo) = makeStore()
        step(undo) { store.addRacer(rank: "CS_3_Bears") }
        let id = try #require(store.selection)
        step(undo) { store.setPhoto(orange, kind: .car, racerID: id) }
        let photo = try #require(store.data.racers[0].carPhoto)
        step(undo) { store.deleteRacer(id) }
        #expect(undo.undoActionName == "Delete Racer")

        undo.undo()
        #expect(store.data.racers.map(\.id) == [id])
        #expect(store.data.racers[0].carPhoto == photo)
        #expect(FileManager.default.fileExists(atPath: store.photoURL(photo).path))

        undo.redo()
        #expect(store.data.racers.isEmpty)
    }

    @Test func typingIsOneUndoStep() throws {
        let (store, undo) = makeStore()
        step(undo) { store.addRacer() }
        let id = try #require(store.selection)
        for name in ["R", "Ro", "Rob", "Robin"] {
            step(undo) { store.binding(id).wrappedValue.firstName = name }
        }
        #expect(store.data.racers[0].firstName == "Robin")
        undo.undo()
        #expect(store.data.racers[0].firstName == "")
        undo.undo()
        #expect(store.data.racers.isEmpty, "the next step back is adding the racer")
    }

    @Test func checkInIsItsOwnStepAfterTyping() throws {
        let (store, undo) = makeStore()
        step(undo) { store.addRacer(rank: "Outlaw") }
        let id = try #require(store.selection)
        step(undo) { store.binding(id).wrappedValue.firstName = "Sam" }
        step(undo) { store.undoable("Check In Sam") { store.binding(id).wrappedValue.checkedInAt = Date() } }
        #expect(undo.undoActionName == "Check In Sam")
        undo.undo()
        #expect(store.data.racers[0].checkedInAt == nil)
        #expect(store.data.racers[0].firstName == "Sam", "undoing the check-in keeps the name")
    }

    @Test func undoClearsASelectionThatNoLongerExists() throws {
        let (store, undo) = makeStore()
        step(undo) { store.addRacer() }
        #expect(store.selection != nil)
        undo.undo()
        #expect(store.selection == nil)
    }

    @Test func undoIsSaved() throws {
        let folder = tempFolder()
        let store = Store(folder: folder)
        let undo = UndoManager()
        store.undoManager = undo
        step(undo) { store.addRacer() }
        undo.undo()
        store.save()
        #expect(Store.event(in: folder)?.racers.isEmpty == true)
    }

    @Test func groupActionsCanBeUndone() throws {
        let (store, undo) = makeStore()
        let bears = try #require(store.data.groups.first { $0.rank == "CS_3_Bears" })
        step(undo) { store.undoable("Rename Group") { store.settingsMessage = store.data.renameRank(bears.id, to: "CS_3_Bear_Cubs") } }
        #expect(store.data.groups.contains { $0.rank == "CS_3_Bear_Cubs" })
        undo.undo()
        #expect(store.data.groups.contains { $0.rank == "CS_3_Bears" })
    }

    @Test func withoutAnUndoManagerNothingIsRecorded() {
        let store = Store(folder: tempFolder())
        store.addRacer()
        #expect(store.data.racers.count == 1, "the web app has no undo manager and still works")
    }
}
