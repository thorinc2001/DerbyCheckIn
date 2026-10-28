import AppKit
import DerbyCore
import SwiftUI

/// Holds the event and saves it, with its photos, to the data folder:
/// ~/Documents/Derby Check-In unless moved (for example to OneDrive or Google Drive) in Settings.
@MainActor
public final class Store: ObservableObject {
    @Published public var data = EventData() {
        didSet {
            guard !isLoading else { return }
            recordUndo(from: oldValue)
            scheduleSave()
        }
    }
    @Published public var selection: Racer.ID?
    /// Shown to the user as an alert.
    @Published public var message: String?
    /// Shown as an alert in the Settings window.
    @Published public var settingsMessage: String?

    @Published public private(set) var folder: URL
    public var photosFolder: URL { folder.appendingPathComponent("Photos", isDirectory: true) }
    private var dataFile: URL { folder.appendingPathComponent("event.json") }
    private var saveTask: Task<Void, Never>?
    private var isLoading = false
    /// The window's undo manager, set by the app. Nil in the web app: browsers have no Undo.
    public weak var undoManager: UndoManager?
    /// Changes until this time join the current undo step, so typing a name is one step.
    private var joinEditsUntil = Date.distantPast
    private var isRestoring = false
    /// False for test stores given their own folder, so they never change the saved setting.
    private let remembersFolder: Bool

    /// Folder name in Documents. Derby Web Check In sets its own so the two apps never share an event by accident.
    public static var appFolderName = "Derby Check-In"
    public static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appFolderName, isDirectory: true)
    }
    private static let folderKey = "dataFolder"

    public init(folder custom: URL? = nil) {
        remembersFolder = custom == nil
        if let custom {
            folder = custom
        } else if let saved = UserDefaults.standard.string(forKey: Self.folderKey) {
            let url = URL(fileURLWithPath: saved, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
                folder = url
            } else {
                // e.g. OneDrive isn't running. Don't write a separate event somewhere else silently.
                folder = Self.defaultFolder
                message = "Your data folder isn't available:\n\(saved)\n\nIf it's in OneDrive or Google Drive, make sure that app is running and signed in, then reopen Derby Check-In. For now the event in Documents is open."
            }
        } else {
            folder = Self.defaultFolder
        }
        load()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        try? FileManager.default.createDirectory(at: photosFolder, withIntermediateDirectories: true)
        guard let raw = try? Data(contentsOf: dataFile) else { return }
        do {
            var loaded = try Self.decoder.decode(EventData.self, from: raw)
            loaded.fillDefaultStartNumbers()
            data = loaded
            removeUnusedPhotos()
        } catch {
            // Keep the unreadable file rather than overwriting it.
            let backup = folder.appendingPathComponent("event-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: dataFile, to: backup)
            message = "The saved event could not be read, so a copy was kept at \(backup.lastPathComponent)."
        }
    }

    // MARK: Data folder

    /// The event saved in a folder, if it has one that can be read.
    public static func event(in folder: URL) -> EventData? {
        guard let raw = try? Data(contentsOf: folder.appendingPathComponent("event.json")) else { return nil }
        return try? decoder.decode(EventData.self, from: raw)
    }

    /// Switches to another data folder. With `bringCurrentEvent`, this event and its photos
    /// are copied there (replacing any event already in it); otherwise the event already
    /// in that folder is opened. The old folder is left untouched as a backup.
    public func useDataFolder(_ newFolder: URL, bringCurrentEvent: Bool) {
        let newFolder = newFolder.standardizedFileURL
        guard newFolder != folder.standardizedFileURL else { return }
        saveTask?.cancel()
        save()
        let fm = FileManager.default
        let newPhotos = newFolder.appendingPathComponent("Photos", isDirectory: true)
        var copied = 0
        do {
            try fm.createDirectory(at: newPhotos, withIntermediateDirectories: true)
            if bringCurrentEvent {
                for r in data.racers {
                    for f in [r.racerPhoto, r.carPhoto].compactMap({ $0 }) {
                        let dest = newPhotos.appendingPathComponent(f)
                        if !fm.fileExists(atPath: dest.path), (try? fm.copyItem(at: photoURL(f), to: dest)) != nil {
                            copied += 1
                        }
                    }
                }
                try Self.encoder.encode(data).write(to: newFolder.appendingPathComponent("event.json"), options: .atomic)
            }
        } catch {
            settingsMessage = "Couldn't use that folder: \(error.localizedDescription)"
            return
        }
        folder = newFolder
        if remembersFolder {
            if newFolder == Self.defaultFolder.standardizedFileURL {
                UserDefaults.standard.removeObject(forKey: Self.folderKey)
            } else {
                UserDefaults.standard.set(newFolder.path, forKey: Self.folderKey)
            }
        }
        selection = nil
        if bringCurrentEvent {
            settingsMessage = "Your event and \(copied) photo\(copied == 1 ? "" : "s") were copied to the new folder, and it's now where everything is saved. The old folder was left as a backup."
        } else {
            isLoading = true
            data = EventData()
            isLoading = false
            load()
            settingsMessage = "Opened the event in the new folder (\(data.racers.count) cars). The old folder was left as it was."
        }
    }

    // MARK: Saving

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            save()
        }
    }

    public func save() {
        do {
            try Self.encoder.encode(data).write(to: dataFile, options: .atomic)
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: Racers

    /// Edits go through the shared check-in rules, so the Mac app and the web
    /// version behave the same.
    public func binding(_ id: Racer.ID) -> Binding<Racer> {
        Binding(
            get: { self.data.racers.first { $0.id == id } ?? Racer(id: id) },
            set: { new in
                if let i = self.data.racers.firstIndex(where: { $0.id == id }) {
                    self.data.racers[i] = self.data.applyingEditRules(new, was: self.data.racers[i])
                }
            }
        )
    }

    public func addRacer(rank: String = "") {
        undoable("New Racer") { selection = data.addRacer(rank: rank).id }
    }

    public func addCar(for racer: Racer) {
        undoable("Add Car") { selection = data.addCar(for: racer).id }
    }

    public func deleteRacer(_ id: Racer.ID) {
        guard let racer = data.racers.first(where: { $0.id == id }) else { return }
        // The photo files stay until the next launch, so Undo can bring the racer back whole.
        undoable("Delete \(racer.fullName.isEmpty ? "Racer" : racer.fullName)") {
            data.racers.removeAll { $0.id == id }
        }
        if selection == id { selection = nil }
    }

    // MARK: Undo

    /// Makes `change` its own undo step, named for the Edit menu ("Undo Delete Robin Avery").
    public func undoable(_ name: String, _ change: () -> Void) {
        joinEditsUntil = .distantPast
        change()
        undoManager?.setActionName(name)
        joinEditsUntil = .distantPast
    }

    /// Every change to the event can be undone. Edits close together (typing) join one step.
    private func recordUndo(from old: EventData) {
        guard let undoManager, !isRestoring else { return }
        let now = Date()
        defer { joinEditsUntil = now.addingTimeInterval(1) }
        guard now >= joinEditsUntil else { return }
        undoManager.registerUndo(withTarget: self) { $0.restore(old) }
        undoManager.setActionName("Edit")
    }

    /// Puts back an earlier event, and registers the reverse so Redo works.
    private func restore(_ snapshot: EventData) {
        let current = data
        undoManager?.registerUndo(withTarget: self) { $0.restore(current) }
        isRestoring = true
        data = snapshot
        isRestoring = false
        joinEditsUntil = .distantPast
        if let id = selection, !data.racers.contains(where: { $0.id == id }) { selection = nil }
    }

    /// Deletes photo files no racer uses. Runs at launch, when there is no undo history to need
    /// them, and only for files unused for a day, so a photo that synced to a shared folder
    /// before its event did isn't removed.
    private func removeUnusedPhotos() {
        let fm = FileManager.default
        let used = Set(data.racers.flatMap { [$0.racerPhoto, $0.carPhoto].compactMap { $0 } })
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let files = (try? fm.contentsOfDirectory(at: photosFolder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where !used.contains(file.lastPathComponent) && file.pathExtension == "jpg" {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantFuture
            if modified < dayAgo { try? fm.removeItem(at: file) }
        }
    }

    // MARK: Photos

    public func photoURL(_ filename: String) -> URL {
        photosFolder.appendingPathComponent(filename)
    }

    public func setPhoto(_ image: NSImage?, kind: PhotoKind, racerID: Racer.ID) {
        guard let i = data.racers.firstIndex(where: { $0.id == racerID }) else { return }
        var newName: String?
        if let image {
            guard let jpeg = image.jpegData() else {
                message = "That image could not be read."
                return
            }
            // A new name each time, so the view reloads the image and Undo never finds it overwritten.
            let name = "\(racerID.uuidString)-\(kind.rawValue)-\(UUID().uuidString.prefix(8)).jpg"
            do {
                try jpeg.write(to: photoURL(name), options: .atomic)
                newName = name
            } catch {
                message = "Could not save the photo: \(error.localizedDescription)"
                return
            }
        }
        // The old file stays until the next launch, so Undo can put it back.
        undoable(newName == nil ? "Remove Photo" : "Set Photo") {
            if kind == .racer { data.racers[i].racerPhoto = newName } else { data.racers[i].carPhoto = newName }
        }
    }

    public func choosePhotoFile(kind: PhotoKind, racerID: Racer.ID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose a \(kind.rawValue) photo"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage(contentsOf: url) else {
            message = "That file isn't an image this app can read."
            return
        }
        setPhoto(image, kind: kind, racerID: racerID)
    }

    public func showDataFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }
}

extension NSImage {
    /// JPEG scaled so its longest side is at most `maxDimension` pixels.
    func jpegData(maxDimension: CGFloat = 1200) -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxDimension / CGFloat(max(cg.width, cg.height)))
        let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let scaled = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
