import Foundation
import Testing
@testable import DerbyCore

/// A made-up roster in GPRM's export format (Tests/Fixtures/sample-roster.csv): CRLF lines,
/// quoting, several cars for one racer, a 20-character car name and a group the app doesn't know yet.
/// The web API test (Tools/api-test.py) uses the same file.
let sampleRoster = try! String(
    contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../Fixtures/sample-roster.csv"),
    encoding: .utf8)

func importedSample() -> EventData {
    var event = EventData()
    _ = event.importRoster(text: sampleRoster)
    return event
}

@Suite("GPRM rosters")
struct RosterTests {
    @Test func importsEveryCar() {
        var event = EventData()
        #expect(event.importRoster(text: sampleRoster) == "Imported 10 cars.")
        #expect(event.racers.count == 10)
        #expect(event.racers.filter { $0.fullName == "Casey Cole" }.count == 3)
    }

    @Test func importingTwiceAddsNothing() {
        var event = importedSample()
        #expect(event.importRoster(text: sampleRoster) == "Imported 0 cars.")
        #expect(event.racers.count == 10)
    }

    @Test func takenCarNumberIsSkippedAndReported() {
        var event = importedSample()
        let summary = event.importRoster(text: "First Name,Last Name,Car#\r\nZed,Zane,405\r\n")
        #expect(summary.contains("Zed Zane: car #405 already belongs to Alex Avery"))
        #expect(event.racers.count == 10)
    }

    /// Exporting what was imported gives back the same file, except Passed: that comes
    /// from this year's inspection, so nothing has passed yet.
    @Test func exportMatchesImportExceptPassed() {
        let exported = GPRM.rosterCSV(importedSample().racers, imageFolderOnPC: "")
        let passedColumn = GPRM.headers.firstIndex(of: "Passed")!
        let expected = CSV.parse(sampleRoster).enumerated().map { line, row in
            var row = row
            if line > 0 { row[passedColumn] = "False" }
            return row.map(CSV.escape).joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
        #expect(exported == expected)
    }

    @Test func importKeepsFlagsAndQuoting() {
        let event = importedSample()
        let byNumber = Dictionary(uniqueKeysWithValues: event.racers.map { ($0.carNumber, $0) })
        #expect(byNumber[1003]?.carName == "Fast, Furious")
        #expect(byNumber[401]?.carName == #"Say "Hi""#)
        #expect(byNumber[400]?.exclude == true)
        #expect(byNumber[401]?.finalist == true)
        #expect(byNumber[705]?.grandFinalist == true)
        #expect(byNumber[101]?.grandTurtle == true)
        #expect(byNumber[1]?.inspection.passed == nil, "Passed is not imported")
    }

    @Test func importAddsUnknownGroupsWithAStartNumber() throws {
        let group = try #require(importedSample().groups.first { $0.rank == "NEW_Rank_X" })
        #expect(group.subgroup == "Mystery Group")
        #expect(group.startNumber == 700)
    }

    @Test func imageFileUsesThePCFolderForCarsWithPhotos() {
        var racer = Racer()
        racer.firstName = "A"; racer.lastName = "B"; racer.carNumber = 42; racer.rank = "R"
        #expect(GPRM.rosterCSV([racer], imageFolderOnPC: #"C:\Derby\Images\"#).hasSuffix(",\r\n"))
        racer.carPhoto = "x.jpg"
        #expect(GPRM.rosterCSV([racer], imageFolderOnPC: #"C:\Derby\Images\"#).hasSuffix(#",C:\Derby\Images\42.jpg"# + "\r\n"))
    }

    @Test func readsTabDelimitedFiles() {
        var event = EventData()
        #expect(event.importRoster(text: "First Name\tLast Name\tDen\nSam\tStone\tCS_3_Bears\n") == "Imported 1 cars.")
        #expect(event.racers.first?.subgroup == "Bears")
    }

    @Test func needsNameColumns() {
        var event = EventData()
        #expect(event.importRoster(text: "Car#,Rank\r\n5,Outlaw\r\n").contains("First Name and Last Name"))
    }

    /// Set DERBY_ROSTER to a real GPRM roster to check it round-trips. Set DERBY_EXPORT_OUT
    /// too and the export is written there, so a refactor can compare it byte for byte.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["DERBY_ROSTER"] != nil))
    func realRosterRoundTrips() throws {
        let env = ProcessInfo.processInfo.environment
        let text = try String(contentsOfFile: env["DERBY_ROSTER"]!, encoding: .utf8)
        var event = EventData()
        _ = event.importRoster(text: text)
        let exported = GPRM.rosterCSV(event.racers, imageFolderOnPC: event.imageFolderOnPC)
        if let out = env["DERBY_EXPORT_OUT"] { try exported.write(toFile: out, atomically: true, encoding: .utf8) }
        let originalRows = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count
        #expect(exported.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == originalRows)
    }
}

@Suite("DerbyNet rosters")
struct DerbyNetRosterTests {
    @Test func rosterHasOneRowPerCarWithTheSubgroupAsGroup() {
        let csv = DerbyNet.rosterCSV(importedSample().racers)
        let rows = CSV.parse(csv)
        #expect(rows[0] == DerbyNet.headers)
        #expect(rows.count == 11)
        #expect(rows.contains(["Alex", "Avery", "405", "Comet", "Bears", "No"]))
        #expect(rows.contains(["Drew", "Diaz", "400", "Bear One", "Bears", "Yes"]), "Exclude becomes Ineligible for Award")
        #expect(rows.contains(["Blair", "Brooks", "1003", "Fast, Furious", "GS_4th_1422", "No"]))
        #expect(csv.contains(#""Say ""Hi""""#))
    }

    @Test func photoNamesKeepOnlyWhatDerbyNetKeeps() {
        var r = Racer()
        r.carNumber = 412
        r.firstName = "José"
        r.lastName = "O'Neil-Ruiz"
        #expect(DerbyNet.photoName(r) == "412 Jose ONeil-Ruiz.jpg")
    }

    @Test func instructionsSayBulkCheckInOnlyWhenEveryoneCheckedIn() {
        var r = Racer()
        #expect(!DerbyNet.instructions([r]).contains("Bulk Check-In"))
        r.checkedInAt = Date()
        #expect(DerbyNet.instructions([r]).contains("Bulk Check-In"))
    }
}
