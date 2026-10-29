import Foundation

/// Reading and writing GrandPrix Race Manager roster files.
public enum GPRM {
    /// GPRM's roster columns, in its order.
    public static let headers = ["First Name", "Last Name", "Car#", "Car Name", "Rank", "Subgroup",
                                 "Passed", "Exclude", "Finalist", "Grand Finalist", "Grand Turtle", "ImageFile"]

    /// A roster GPRM can import: CRLF line endings and no byte-order mark, like GPRM's own export.
    /// `imageFolderOnPC` fills ImageFile as <folder>\<car#>.jpg for cars with a photo; blank leaves it empty.
    public static func rosterCSV(_ racers: [Racer], imageFolderOnPC: String) -> String {
        let pcFolder = imageFolderOnPC.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\\"))
        func flag(_ b: Bool) -> String { b ? "True" : "False" }
        var lines = [headers.map(CSV.escape).joined(separator: ",")]
        for r in racers {
            let imageFile = !pcFolder.isEmpty && (r.racerPhoto != nil || r.carPhoto != nil) ? "\(pcFolder)\\\(r.carNumber).jpg" : ""
            let fields = [
                r.firstName, r.lastName, String(r.carNumber), String(r.carName.prefix(maxCarNameLength)),
                r.rank, r.subgroup.isEmpty ? r.rank : r.subgroup,
                flag(r.inspection.passed == true), flag(r.exclude), flag(r.finalist),
                flag(r.grandFinalist), flag(r.grandTurtle), imageFile,
            ]
            lines.append(fields.map(CSV.escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }
}

/// Files for DerbyNet (github.com/jeffpiazza/derbynet), carried to its computer on a USB drive.
/// Its Import Roster page doesn't read header names: each column is matched by dragging a label.
public enum DerbyNet {
    public static let headers = ["First Name", "Last Name", "Car Number", "Car Name", "Group", "Ineligible for Award"]

    /// The roster for Set-Up › Import Roster, in UTF-8. Group is the Subgroup ("Bears"), DerbyNet's den name.
    /// Inspection and photos can't go in a roster: the instructions cover them.
    public static func rosterCSV(_ racers: [Racer]) -> String {
        var lines = [headers.map(CSV.escape).joined(separator: ",")]
        for r in racers {
            let fields = [r.firstName, r.lastName, String(r.carNumber), r.carName, r.groupName, r.exclude ? "Yes" : "No"]
            lines.append(fields.map(CSV.escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// "412 Robin Avery.jpg": the car number to find the racer, then the name to check it.
    /// Only the characters DerbyNet keeps in uploaded file names, so it shows the name unchanged.
    public static func photoName(_ r: Racer) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789- ")
        let name = String(String.UnicodeScalarView(r.fullName.decomposedStringWithCanonicalMapping.unicodeScalars
            .filter { allowed.contains($0) }))
        return "\(r.carNumber) \(name)".trimmingCharacters(in: .whitespaces) + ".jpg"
    }

    public static let instructionsFile = "How to Import into DerbyNet.txt"

    /// The steps at the DerbyNet computer, saved next to the roster.
    public static func instructions(_ racers: [Racer]) -> String {
        let checkIn = racers.allSatisfy(\.isCheckedIn)
            ? """
              Every racer in this export passed check-in. On the Race Check-In page, click Bulk,
                 choose All, and click Bulk Check-In.
              """
            : """
              This export includes racers who have not checked in. On the Race Check-In page,
                 check in only the racers who passed.
              """
        return """
            Importing into DerbyNet

            1. Copy this folder to the DerbyNet computer, or to any computer that can open DerbyNet.
               Log in to DerbyNet as the Race Coordinator.

            2. Set-Up › Import Roster: choose "DerbyNet Roster.csv". If any names have accents,
               set Encoding to UTF-8. Drag each label onto its column: First Name, Last Name,
               Car Number, Car Name, the group label (Den, Group, …) onto Group, and
               "Ineligible for Award?" onto Ineligible for Award. Click Import Roster and
               approve the new groups.

            3. \(checkIn)

            4. Racer Photos: drag every file in "Racer Photos" onto the upload area. Each file is
               named by car number and racer, so drag each photo onto its racer.
               Car Photos: do the same with the "Car Photos" folder.

            Weight, the inspection checklist and notes stay in Derby Check-In: DerbyNet has no
            place for them.

            """.replacingOccurrences(of: "\n", with: "\r\n")
    }
}

public enum CSV {
    public static func escape(_ field: String) -> String {
        let flat = field.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        guard flat.contains(where: { $0 == "," || $0 == "\"" }) else { return flat }
        return "\"" + flat.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Rows of a CSV, or of a tab-delimited file when the first line has tabs and no commas.
    public static func parse(_ text: String) -> [[String]] {
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

public extension EventData {
    /// Adds the racers in a roster file and returns a summary for the user.
    /// Inspection and check-in are not imported: they happen at this year's check-in.
    mutating func importRoster(text: String) -> String {
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

            if r.carNumber > 0, let other = racers.first(where: { $0.carNumber == r.carNumber }) {
                if other.fullName.caseInsensitiveCompare(r.fullName) != .orderedSame {
                    skipped.append("\(r.fullName): car #\(r.carNumber) already belongs to \(other.fullName)")
                }
                continue  // Same racer and car already here: importing twice changes nothing.
            }
            if r.carNumber == 0, racers.contains(where: { $0.fullName.caseInsensitiveCompare(r.fullName) == .orderedSame }) {
                continue
            }
            if !r.rank.isEmpty {
                if let group = groups.first(where: { $0.rank == r.rank }) {
                    if r.subgroup.isEmpty { r.subgroup = group.subgroup }
                } else {
                    groups.append(RaceGroup(rank: r.rank, subgroup: r.subgroup.isEmpty ? r.rank : r.subgroup))
                }
            }
            racers.append(r)
            added += 1
        }
        // A group the import created starts its series at its lowest car, rounded down to the hundred.
        for i in groups.indices where groups[i].startNumber == 0 {
            if let low = racers.filter({ $0.rank == groups[i].rank && $0.carNumber > 0 }).map(\.carNumber).min() {
                groups[i].startNumber = low >= 100 ? low / 100 * 100 : low
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
