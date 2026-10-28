import DerbyCore
import AppKit

/// `DerbyCheckIn --storagetest <scratch folder>` checks cloud-folder detection and moving
/// the event between data folders, using stand-in OneDrive and Google Drive folders.
@MainActor
enum StorageTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--storagetest"), args.count > i + 1 else { return }
        let root = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        let fm = FileManager.default
        var failed = 0
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "PASS " : "FAIL ") + name)
            if !ok { failed += 1 }
        }
        let savedSetting = UserDefaults.standard.string(forKey: "dataFolder")

        // Stand-in home with the folders the OneDrive and Google Drive apps create.
        let home = root.appendingPathComponent("home", isDirectory: true)
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        try? fm.createDirectory(at: storage.appendingPathComponent("OneDrive-Personal"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: storage.appendingPathComponent("GoogleDrive-pack352@gmail.com/My Drive"), withIntermediateDirectories: true)
        let clouds = CloudFolder.detect(home: home)
        check("finds OneDrive and Google Drive", clouds.map(\.name) == ["Google Drive (pack352@gmail.com)", "OneDrive – Personal"])
        check("Google Drive uses My Drive", clouds.first?.url.lastPathComponent == "My Drive")

        // An event on "this Mac" with one racer and a photo.
        let local = root.appendingPathComponent("local", isDirectory: true)
        let store = Store(folder: local)
        store.addRacer(rank: "CS_3_Bears")
        let id = store.data.racers[0].id
        store.data.racers[0].firstName = "Jordan"
        store.data.racers[0].lastName = "Reed"
        let image = NSImage(size: NSSize(width: 40, height: 30), flipped: false) { r in NSColor.orange.setFill(); r.fill(); return true }
        store.setPhoto(image, kind: .car, racerID: id)
        store.data.groups[0].startNumber = 150
        store.save()

        let oneDrive = clouds[1].url.appendingPathComponent("Derby Check-In", isDirectory: true)
        check("empty cloud folder has no event", Store.event(in: oneDrive) == nil)
        store.useDataFolder(oneDrive, bringCurrentEvent: true)
        let photo = store.data.racers[0].carPhoto ?? ""
        check("store now saves to OneDrive", store.folder.standardizedFileURL == oneDrive.standardizedFileURL)
        check("event copied to OneDrive", Store.event(in: oneDrive)?.racers.first?.fullName == "Jordan Reed")
        check("photo copied to OneDrive", fm.fileExists(atPath: oneDrive.appendingPathComponent("Photos/\(photo)").path))
        check("groups and start numbers copied", Store.event(in: oneDrive)?.groups[0].startNumber == 150)
        check("old folder kept as backup", Store.event(in: local)?.racers.count == 1)
        check("OneDrive folder recognised", CloudFolder.service(of: store.folder, in: clouds)?.service == .oneDrive)

        store.data.racers[0].carName = "Aura"
        store.save()
        check("later saves go to OneDrive", Store.event(in: oneDrive)?.racers.first?.carName == "Aura"
              && Store.event(in: local)?.racers.first?.carName == "")

        // A second Mac opening the shared event instead of replacing it.
        let other = Store(folder: root.appendingPathComponent("other-mac", isDirectory: true))
        other.addRacer(rank: "Outlaw")
        other.useDataFolder(oneDrive, bringCurrentEvent: false)
        check("opening an existing event loads it", other.data.racers.count == 1 && other.data.racers[0].fullName == "Jordan Reed")
        check("photos are found in the shared folder", other.data.racers[0].carPhoto.map { fm.fileExists(atPath: other.photoURL($0).path) } == true)

        check("test runs leave the saved folder setting alone", UserDefaults.standard.string(forKey: "dataFolder") == savedSetting)
        print(failed == 0 ? "All checks passed" : "\(failed) checks failed")
        exit(failed == 0 ? 0 : 1)
    }
}
