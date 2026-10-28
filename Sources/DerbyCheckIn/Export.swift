import AppKit
import DerbyCore

/// Import and export on the Mac: file panels and the export folder around the shared roster code.
extension Store {
    func export(checkedInOnly: Bool) {
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
            let dir = try writeExport(racers, into: base)
            let photos = racers.filter { $0.racerPhoto != nil || $0.carPhoto != nil }.count
            message = "Exported \(racers.count) cars (\(photos) with photos) to “\(dir.lastPathComponent)”."
            NSWorkspace.shared.activateFileViewerSelecting([dir])
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Writes "GPRM Roster.csv" plus photos named by car number, and returns the new folder.
    /// Images/<car#>.jpg is the racer photo (or the car photo if there is none) and is what
    /// the ImageFile column points to; Car Photos/<car#>.jpg holds every car photo.
    func writeExport(_ racers: [Racer], into base: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let dir = base.appendingPathComponent("\(data.eventName) Export \(formatter.string(from: Date()))", isDirectory: true)
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
        return dir
    }

    func importRoster() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText]
        panel.message = "Choose a GPRM roster or other CSV with a header row (First Name, Last Name, Car#, Rank…)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let text = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .windowsCP1252)) else {
            message = "That file could not be read."
            return
        }
        message = data.importRoster(text: text)
    }
}
