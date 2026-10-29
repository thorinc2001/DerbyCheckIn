import AppKit
import DerbyCore

/// The race program an export folder is for.
public enum ExportTarget: String, Sendable {
    case gprm, derbyNet

    public var name: String { self == .gprm ? "GPRM" : "DerbyNet" }
}

/// Import and export on the Mac: file panels and the export folder around the shared roster code.
extension Store {
    public func export(checkedInOnly: Bool, for target: ExportTarget = .gprm) {
        let racers = (checkedInOnly ? data.racers.filter(\.isCheckedIn) : data.racers).sorted(by: Racer.displayOrder)
        guard !racers.isEmpty else {
            message = checkedInOnly ? "No racers are checked in yet." : "There are no racers to export."
            return
        }
        let problems = data.exportProblems(racers)
        guard problems.isEmpty else {
            message = "Fix these before exporting:\n\n" + problems.prefix(12).joined(separator: "\n")
                + (problems.count > 12 ? "\n…and \(problems.count - 12) more." : "")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to put the export folder (for example a USB drive)."
        guard panel.runModal() == .OK, let base = panel.url else { return }

        do {
            let dir = try writeExport(racers, into: base, for: target)
            let photos = racers.filter { $0.racerPhoto != nil || $0.carPhoto != nil }.count
            message = "Exported \(racers.count) cars (\(photos) with photos) to “\(dir.lastPathComponent)”."
                + (target == .derbyNet ? "\n\n“\(DerbyNet.instructionsFile)” in the folder has the steps for DerbyNet." : "")
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Writes the export folder for `target` into `base` and returns it.
    public func writeExport(_ racers: [Racer], into base: URL, for target: ExportTarget = .gprm) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let label = target == .gprm ? "Export" : "DerbyNet Export"
        let dir = base.appendingPathComponent("\(data.eventName) \(label) \(formatter.string(from: Date()))", isDirectory: true)
        switch target {
        case .gprm: try writeGPRMExport(racers, into: dir)
        case .derbyNet: try writeDerbyNetExport(racers, into: dir)
        }
        return dir
    }

    /// "GPRM Roster.csv" plus photos named by car number.
    /// Images/<car#>.jpg is the racer photo (or the car photo if there is none) and is what
    /// the ImageFile column points to; Car Photos/<car#>.jpg holds every car photo.
    private func writeGPRMExport(_ racers: [Racer], into dir: URL) throws {
        let images = dir.appendingPathComponent("Images", isDirectory: true)
        let carPhotos = dir.appendingPathComponent("Car Photos", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: images, withIntermediateDirectories: true)
        try fm.createDirectory(at: carPhotos, withIntermediateDirectories: true)

        try GPRM.rosterCSV(racers, imageFolderOnPC: data.imageFolderOnPC).write(
            to: dir.appendingPathComponent("GPRM Roster.csv"), atomically: true, encoding: .utf8)

        for r in racers {
            if let f = r.racerPhoto ?? r.carPhoto {
                try fm.copyItem(at: photoURL(f), to: images.appendingPathComponent("\(r.carNumber).jpg"))
            }
            if let f = r.carPhoto {
                try fm.copyItem(at: photoURL(f), to: carPhotos.appendingPathComponent("\(r.carNumber).jpg"))
            }
        }
    }

    /// "DerbyNet Roster.csv", the steps for DerbyNet, and Racer Photos and Car Photos named
    /// "<car#> <name>.jpg" for assigning by hand.
    private func writeDerbyNetExport(_ racers: [Racer], into dir: URL) throws {
        let racerPhotos = dir.appendingPathComponent("Racer Photos", isDirectory: true)
        let carPhotos = dir.appendingPathComponent("Car Photos", isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: racerPhotos, withIntermediateDirectories: true)
        try fm.createDirectory(at: carPhotos, withIntermediateDirectories: true)

        try DerbyNet.rosterCSV(racers).write(to: dir.appendingPathComponent("DerbyNet Roster.csv"), atomically: true, encoding: .utf8)
        try DerbyNet.instructions(racers).write(
            to: dir.appendingPathComponent(DerbyNet.instructionsFile), atomically: true, encoding: .utf8)

        for r in racers {
            if let f = r.racerPhoto {
                try fm.copyItem(at: photoURL(f), to: racerPhotos.appendingPathComponent(DerbyNet.photoName(r)))
            }
            if let f = r.carPhoto {
                try fm.copyItem(at: photoURL(f), to: carPhotos.appendingPathComponent(DerbyNet.photoName(r)))
            }
        }
    }

    public func importRoster() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        panel.message = "Choose a GPRM roster or other CSV with a header row (First Name, Last Name, Car#, Rank…)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .windowsCP1252)) else {
            message = "That file could not be read."
            return
        }
        undoable("Import Roster") { message = data.importRoster(text: text) }
    }
}
