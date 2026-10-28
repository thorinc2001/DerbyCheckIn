import AppKit

/// The roster columns GrandPrix Race Manager exports and imports, in its order.
func gprmColumns(imageFile: @escaping (Racer) -> String) -> [(header: String, value: (Racer) -> String)] {
    func flag(_ b: Bool) -> String { b ? "True" : "False" }
    return [
        ("First Name", { $0.firstName }),
        ("Last Name", { $0.lastName }),
        ("Car#", { String($0.carNumber) }),
        ("Car Name", { String($0.carName.prefix(maxCarNameLength)) }),
        ("Rank", { $0.rank }),
        ("Subgroup", { $0.subgroup.isEmpty ? $0.rank : $0.subgroup }),
        ("Passed", { flag($0.inspection.passed == true) }),
        ("Exclude", { flag($0.exclude) }),
        ("Finalist", { flag($0.finalist) }),
        ("Grand Finalist", { flag($0.grandFinalist) }),
        ("Grand Turtle", { flag($0.grandTurtle) }),
        ("ImageFile", imageFile),
    ]
}

enum CSV {
    static func escape(_ field: String) -> String {
        let flat = field.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard flat.contains(where: { $0 == "," || $0 == "\"" }) else { return flat }
        return "\"" + flat.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func parse(_ text: String) -> [[String]] {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" && $0 != "\r" }
        let delimiter: Character = firstLine.contains("\t") && !firstLine.contains(",") ? "\t" : ","
        var rows: [[String]] = [], row: [String] = [], field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); rows.append(row); row = []; field = ""
            } else {
                field.append(c)
            }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

extension Store {
    /// Problems GPRM would reject, or that would make the import wrong.
    func exportProblems(_ racers: [Racer]) -> [String] {
        var problems: [String] = []
        for r in racers {
            let name = r.fullName.isEmpty ? "A racer with no name" : r.fullName
            if r.firstName.isEmpty || r.lastName.isEmpty { problems.append("\(name) is missing a first or last name.") }
            if r.carNumber <= 0 { problems.append("\(name) has no car number.") }
            if r.rank.isEmpty { problems.append("\(name) (car #\(r.carNumber)) has no race group.") }
        }
        let counts = Dictionary(grouping: racers.filter { $0.carNumber > 0 }, by: \.carNumber)
        for (number, rs) in counts.sorted(by: { $0.key < $1.key }) where rs.count > 1 {
            problems.append("Car #\(number) is used by \(rs.map(\.fullName).joined(separator: ", ")).")
        }
        return problems
    }

    func export(checkedInOnly: Bool) {
        let racers = (checkedInOnly ? data.racers.filter(\.isCheckedIn) : data.racers)
            .sorted { ($0.lastName.lowercased(), $0.firstName.lowercased(), $0.carNumber) < ($1.lastName.lowercased(), $1.firstName.lowercased(), $1.carNumber) }
        guard !racers.isEmpty else {
            message = checkedInOnly ? "No racers are checked in yet." : "There are no racers to export."
            return
        }
        let problems = exportProblems(racers)
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

        let pcFolder = data.imageFolderOnPC.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
        let columns = gprmColumns { r in
            guard !pcFolder.isEmpty, r.racerPhoto != nil || r.carPhoto != nil else { return "" }
            return "\(pcFolder)\\\(r.carNumber).jpg"
        }
        var lines = [columns.map { CSV.escape($0.header) }.joined(separator: ",")]
        for r in racers {
            lines.append(columns.map { CSV.escape($0.value(r)) }.joined(separator: ","))
        }
        // CRLF and no byte-order mark, like GPRM's own export.
        try (lines.joined(separator: "\r\n") + "\r\n").write(
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
        message = importRoster(text: text)
    }

    /// Adds the racers in a roster file and returns a summary for the user.
    /// Inspection and check-in are not imported: they happen at this year's check-in.
    func importRoster(text: String) -> String {
        var rows = CSV.parse(text).filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard !rows.isEmpty else { return "That file is empty." }
        let header = rows.removeFirst().map { $0.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "#" } }

        func column(_ names: String...) -> Int? { header.firstIndex { names.contains($0) } }
        let first = column("firstname", "first")
        let last = column("lastname", "last")
        let carNumber = column("car#", "carnumber", "carno", "vehicle#", "vehiclenumber", "number", "#")
        let carName = column("carname", "vehiclename")
        let rank = column("rank", "group", "den", "racegroup", "class")
        let subgroup = column("subgroup")
        let exclude = column("exclude")
        let finalist = column("finalist")
        let grandFinalist = column("grandfinalist")
        let grandTurtle = column("grandturtle")
        guard let first, let last else {
            return "The file needs a header row with First Name and Last Name columns."
        }

        func cell(_ row: [String], _ index: Int?) -> String {
            guard let index, index < row.count else { return "" }
            return row[index].trimmingCharacters(in: .whitespaces)
        }
        func flag(_ row: [String], _ index: Int?) -> Bool {
            ["true", "yes", "1", "x"].contains(cell(row, index).lowercased())
        }

        var added = 0
        var skipped: [String] = []
        for row in rows {
            var r = Racer()
            r.firstName = cell(row, first)
            r.lastName = cell(row, last)
            guard !r.firstName.isEmpty || !r.lastName.isEmpty else { continue }
            r.carNumber = Int(cell(row, carNumber)) ?? 0
            r.carName = String(cell(row, carName).prefix(maxCarNameLength))
            r.rank = cell(row, rank)
            r.subgroup = cell(row, subgroup)
            r.exclude = flag(row, exclude)
            r.finalist = flag(row, finalist)
            r.grandFinalist = flag(row, grandFinalist)
            r.grandTurtle = flag(row, grandTurtle)

            if r.carNumber > 0, let other = data.racers.first(where: { $0.carNumber == r.carNumber }) {
                if other.fullName.caseInsensitiveCompare(r.fullName) != .orderedSame {
                    skipped.append("\(r.fullName): car #\(r.carNumber) already belongs to \(other.fullName)")
                }
                continue  // Same racer and car already here: importing twice changes nothing.
            }
            if r.carNumber == 0, data.racers.contains(where: { $0.fullName.caseInsensitiveCompare(r.fullName) == .orderedSame }) {
                continue
            }
            if !r.rank.isEmpty {
                if let group = data.groups.first(where: { $0.rank == r.rank }) {
                    if r.subgroup.isEmpty { r.subgroup = group.subgroup }
                } else {
                    data.groups.append(RaceGroup(rank: r.rank, subgroup: r.subgroup.isEmpty ? r.rank : r.subgroup))
                }
            }
            data.racers.append(r)
            added += 1
        }
        // A group the import created starts its series at its lowest car, rounded down to the hundred.
        for i in data.groups.indices where data.groups[i].startNumber == 0 {
            if let low = data.racers.filter({ $0.rank == data.groups[i].rank && $0.carNumber > 0 }).map(\.carNumber).min() {
                data.groups[i].startNumber = low >= 100 ? low / 100 * 100 : low
            }
        }
        var summary = "Imported \(added) cars."
        if !skipped.isEmpty {
            summary += "\n\nSkipped because the car number is taken:\n" + skipped.prefix(10).joined(separator: "\n")
                + (skipped.count > 10 ? "\n…and \(skipped.count - 10) more." : "")
        }
        return summary
    }
}
