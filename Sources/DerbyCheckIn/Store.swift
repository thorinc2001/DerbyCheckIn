import AppKit
import SwiftUI

/// Holds the event and saves it, with its photos, to the data folder:
/// ~/Documents/Derby Check-In unless moved (for example to OneDrive or Google Drive) in Settings.
@MainActor
final class Store: ObservableObject {
    @Published var data = EventData() { didSet { if !isLoading { scheduleSave() } } }
    @Published var selection: Racer.ID?
    /// Shown to the user as an alert.
    @Published var message: String?
    /// Shown as an alert in the Settings window.
    @Published var settingsMessage: String?

    @Published private(set) var folder: URL
    var photosFolder: URL { folder.appendingPathComponent("Photos", isDirectory: true) }
    private var dataFile: URL { folder.appendingPathComponent("event.json") }
    private var saveTask: Task<Void, Never>?
    private var isLoading = false
    /// False for test stores given their own folder, so they never change the saved setting.
    private let remembersFolder: Bool

    /// Folder name in Documents. Derby Web Check In sets its own so the two apps never share an event by accident.
    static var appFolderName = "Derby Check-In"
    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appFolderName, isDirectory: true)
    }
    private static let folderKey = "dataFolder"

    init(folder custom: URL? = nil) {
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
            data = try Self.decoder.decode(EventData.self, from: raw)
            // Groups saved before start numbers existed get the pack's usual series.
            for i in data.groups.indices where data.groups[i].startNumber == 0 {
                data.groups[i].startNumber = RaceGroup.defaults.first { $0.rank == data.groups[i].rank }?.startNumber ?? 0
            }
        } catch {
            // Keep the unreadable file rather than overwriting it.
            let backup = folder.appendingPathComponent("event-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: dataFile, to: backup)
            message = "The saved event could not be read, so a copy was kept at \(backup.lastPathComponent)."
        }
    }

    // MARK: Data folder

    /// The event saved in a folder, if it has one that can be read.
    static func event(in folder: URL) -> EventData? {
        guard let raw = try? Data(contentsOf: folder.appendingPathComponent("event.json")) else { return nil }
        return try? decoder.decode(EventData.self, from: raw)
    }

    /// Switches to another data folder. With `bringCurrentEvent`, this event and its photos
    /// are copied there (replacing any event already in it); otherwise the event already
    /// in that folder is opened. The old folder is left untouched as a backup.
    func useDataFolder(_ newFolder: URL, bringCurrentEvent: Bool) {
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

    func save() {
        do {
            try Self.encoder.encode(data).write(to: dataFile, options: .atomic)
        } catch {
            message = "Could not save: \(error.localizedDescription)"
        }
    }

    // MARK: Racers

    func binding(_ id: Racer.ID) -> Binding<Racer> {
        Binding(
            get: { self.data.racers.first { $0.id == id } ?? Racer(id: id) },
            set: { new in
                if let i = self.data.racers.firstIndex(where: { $0.id == id }) {
                    self.data.racers[i] = new
                }
            }
        )
    }

    func addRacer(rank: String = "") {
        var racer = Racer()
        if let group = data.groups.first(where: { $0.rank == rank }) {
            racer.rank = group.rank
            racer.subgroup = group.subgroup
            racer.carNumber = nextCarNumber(for: racer)
        }
        data.racers.append(racer)
        selection = racer.id
    }

    /// Adds another car for the same racer (GPRM allows one racer several cars).
    func addCar(for racer: Racer) {
        var car = Racer()
        car.firstName = racer.firstName
        car.lastName = racer.lastName
        car.rank = racer.rank
        car.subgroup = racer.subgroup
        car.carNumber = nextCarNumber(for: car)
        data.racers.append(car)
        selection = car.id
    }

    func deleteRacer(_ id: Racer.ID) {
        guard let racer = data.racers.first(where: { $0.id == id }) else { return }
        for file in [racer.racerPhoto, racer.carPhoto].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: photosFolder.appendingPathComponent(file))
        }
        data.racers.removeAll { $0.id == id }
        if selection == id { selection = nil }
    }

    /// Next free number in the rank's own series (e.g. Bears 400, 401, …).
    /// Uses the group's start number when it has one; otherwise continues after the
    /// group's highest car, or starts at the next free hundred.
    func nextCarNumber(for racer: Racer) -> Int {
        let others = data.racers.filter { $0.id != racer.id }
        let used = Set(others.map(\.carNumber))
        var n: Int
        if let start = data.groups.first(where: { $0.rank == racer.rank })?.startNumber, start > 0 {
            n = start
        } else if let max = others.filter({ $0.rank == racer.rank && $0.carNumber > 0 }).map(\.carNumber).max() {
            n = max + 1
        } else {
            n = ((others.map(\.carNumber).max() ?? 0) / 100 + 1) * 100
        }
        while used.contains(n) { n += 1 }
        return n
    }

    // MARK: Race groups

    /// Shown in the Race Groups window.
    func carCount(rank: String) -> Int {
        data.racers.filter { $0.rank == rank }.count
    }

    func addGroup() {
        let highest = max(data.groups.map(\.startNumber).max() ?? 0, data.racers.map(\.carNumber).max() ?? 0)
        var n = 1
        while data.groups.contains(where: { $0.rank == "New_Group_\(n)" }) { n += 1 }
        data.groups.append(RaceGroup(rank: "New_Group_\(n)", subgroup: "New Group \(n)",
                                     startNumber: (highest / 100 + 1) * 100))
    }

    /// Renames a group's Rank and moves its cars with it.
    func renameRank(_ id: RaceGroup.ID, to newRank: String) {
        guard let i = data.groups.firstIndex(where: { $0.id == id }) else { return }
        let old = data.groups[i].rank
        let rank = newRank.trimmingCharacters(in: .whitespaces)
        guard rank != old else { return }
        if rank.isEmpty {
            settingsMessage = "A group's Rank can't be blank."
            return
        }
        if data.groups.contains(where: { $0.id != id && $0.rank.caseInsensitiveCompare(rank) == .orderedSame }) {
            settingsMessage = "There is already a group with the Rank “\(rank)”."
            return
        }
        data.groups[i].rank = rank
        for j in data.racers.indices where data.racers[j].rank == old {
            data.racers[j].rank = rank
        }
    }

    /// Changes a group's Subgroup (display name) and updates its cars.
    func renameSubgroup(_ id: RaceGroup.ID, to newName: String) {
        guard let i = data.groups.firstIndex(where: { $0.id == id }) else { return }
        let rank = data.groups[i].rank
        let name = newName.trimmingCharacters(in: .whitespaces)
        data.groups[i].subgroup = name.isEmpty ? rank : name
        for j in data.racers.indices where data.racers[j].rank == rank {
            data.racers[j].subgroup = data.groups[i].subgroup
        }
    }

    func setStartNumber(_ id: RaceGroup.ID, to start: Int) {
        guard let i = data.groups.firstIndex(where: { $0.id == id }) else { return }
        data.groups[i].startNumber = max(0, start)
    }

    /// Why a group's start number may cause trouble, or nil.
    func startNumberProblem(_ group: RaceGroup) -> String? {
        guard group.startNumber > 0 else { return nil }
        if let other = data.groups.first(where: { $0.id != group.id && $0.startNumber == group.startNumber }) {
            return "Same start as \(other.subgroup.isEmpty ? other.rank : other.subgroup)"
        }
        return nil
    }

    func deleteGroup(_ id: RaceGroup.ID) {
        guard let group = data.groups.first(where: { $0.id == id }) else { return }
        let count = carCount(rank: group.rank)
        guard count == 0 else {
            settingsMessage = "\(count) car\(count == 1 ? " is" : "s are") in \(group.name). Move them to another group first."
            return
        }
        data.groups.removeAll { $0.id == id }
    }

    /// Gives every car in the group a number from its start, in name order.
    /// With `onlyUnnumbered`, cars that already have a number keep it.
    func renumber(_ id: RaceGroup.ID, onlyUnnumbered: Bool) {
        guard let group = data.groups.first(where: { $0.id == id }), group.startNumber > 0 else { return }
        let targets = data.racers.indices
            .filter { data.racers[$0].rank == group.rank && (!onlyUnnumbered || data.racers[$0].carNumber <= 0) }
            .sorted {
                let a = data.racers[$0], b = data.racers[$1]
                return (a.lastName.lowercased(), a.firstName.lowercased(), a.carNumber) < (b.lastName.lowercased(), b.firstName.lowercased(), b.carNumber)
            }
        let targetIDs = Set(targets.map { data.racers[$0].id })
        var used = Set(data.racers.filter { !targetIDs.contains($0.id) }.map(\.carNumber))
        var racers = data.racers
        var n = group.startNumber
        for i in targets {
            while used.contains(n) { n += 1 }
            racers[i].carNumber = n
            used.insert(n)
        }
        data.racers = racers
        settingsMessage = "Numbered \(targets.count) car\(targets.count == 1 ? "" : "s") in \(group.name) starting at \(group.startNumber)."
    }

    func carNumberProblem(for racer: Racer) -> String? {
        if racer.carNumber <= 0 { return "Needs a car number (a whole number above 0)." }
        if let other = data.racers.first(where: { $0.id != racer.id && $0.carNumber == racer.carNumber }) {
            let name = other.fullName.isEmpty ? "another racer" : other.fullName
            return "Car #\(racer.carNumber) is already used by \(name)."
        }
        return nil
    }

    /// Why this racer can't be checked in yet, or nil if they can.
    func checkInBlocker(_ racer: Racer) -> String? {
        if racer.firstName.trimmingCharacters(in: .whitespaces).isEmpty
            || racer.lastName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Enter the racer's first and last name."
        }
        if racer.rank.isEmpty { return "Choose a race group (rank)." }
        return carNumberProblem(for: racer)
    }

    // MARK: Photos

    func photoURL(_ filename: String) -> URL {
        photosFolder.appendingPathComponent(filename)
    }

    func setPhoto(_ image: NSImage?, kind: PhotoKind, racerID: Racer.ID) {
        guard let i = data.racers.firstIndex(where: { $0.id == racerID }) else { return }
        let old = kind == .racer ? data.racers[i].racerPhoto : data.racers[i].carPhoto
        var newName: String?
        if let image {
            guard let jpeg = image.jpegData() else {
                message = "That image could not be read."
                return
            }
            // A new name each time so the view reloads the image.
            let name = "\(racerID.uuidString)-\(kind.rawValue)-\(Int(Date().timeIntervalSince1970)).jpg"
            do {
                try jpeg.write(to: photoURL(name), options: .atomic)
                newName = name
            } catch {
                message = "Could not save the photo: \(error.localizedDescription)"
                return
            }
        }
        if let old { try? FileManager.default.removeItem(at: photoURL(old)) }
        if kind == .racer { data.racers[i].racerPhoto = newName } else { data.racers[i].carPhoto = newName }
    }

    func choosePhotoFile(kind: PhotoKind, racerID: Racer.ID) {
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

    func showDataFolder() {
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
