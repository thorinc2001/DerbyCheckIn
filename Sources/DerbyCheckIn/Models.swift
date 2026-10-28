import Foundation

/// GPRM truncates car names longer than this.
let maxCarNameLength = 20

struct Racer: Identifiable, Codable, Hashable {
    var id = UUID()
    /// 0 means "not assigned yet". GPRM requires a positive, unique whole number.
    var carNumber = 0
    var firstName = ""
    var lastName = ""
    /// GPRM "Rank": the race group, e.g. CS_3_Bears.
    var rank = ""
    /// GPRM "Subgroup": the group's display name, e.g. Bears.
    var subgroup = ""
    var carName = ""
    /// 0 means "not weighed yet". Used for inspection only; GPRM's roster has no weight column.
    var weightOz = 0.0
    var inspection = Inspection()
    var notes = ""
    /// File names inside the event's Photos folder.
    var racerPhoto: String?
    var carPhoto: String?
    var checkedInAt: Date?
    // GPRM flags, carried through import and export.
    var exclude = false
    var finalist = false
    var grandFinalist = false
    var grandTurtle = false

    var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    var groupName: String { subgroup.isEmpty ? rank : subgroup }

    var isCheckedIn: Bool { checkedInAt != nil }
}

struct Inspection: Codable, Hashable {
    var weightOK = false
    var dimensionsOK = false
    var clearanceOK = false
    var wheelsAxlesOK = false
    var noLooseParts = false
    /// nil = not inspected yet.
    var passed: Bool?

    var allChecked: Bool {
        weightOK && dimensionsOK && clearanceOK && wheelsAxlesOK && noLooseParts
    }
}

/// A GPRM race group: a Rank and the Subgroup name shown for it.
struct RaceGroup: Codable, Hashable, Identifiable {
    var id = UUID()
    var rank: String
    var subgroup: String
    /// First car number for this group's series (e.g. 400 for Bears). 0 = no set start.
    var startNumber = 0

    var name: String { subgroup.isEmpty || subgroup == rank ? rank : "\(subgroup) (\(rank))" }

    init(rank: String, subgroup: String, startNumber: Int = 0) {
        self.rank = rank
        self.subgroup = subgroup
        self.startNumber = startNumber
    }

    // Groups saved before id and startNumber existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        rank = try c.decode(String.self, forKey: .rank)
        subgroup = try c.decodeIfPresent(String.self, forKey: .subgroup) ?? ""
        startNumber = try c.decodeIfPresent(Int.self, forKey: .startNumber) ?? 0
    }

    /// The pack's groups and number series, from its GPRM roster.
    static let defaults = [
        RaceGroup(rank: "CS_K_Lions", subgroup: "Lions", startNumber: 100),
        RaceGroup(rank: "CS_2_Wolves", subgroup: "Wolves", startNumber: 300),
        RaceGroup(rank: "CS_3_Bears", subgroup: "Bears", startNumber: 400),
        RaceGroup(rank: "CS_4_Webelos", subgroup: "Webelos", startNumber: 500),
        RaceGroup(rank: "CS_5_AOL", subgroup: "Arrow of Light", startNumber: 600),
        RaceGroup(rank: "GS_2nd_1486", subgroup: "GS_2nd_1486", startNumber: 800),
        RaceGroup(rank: "GS_3rd_1461", subgroup: "GS_3rd_1461", startNumber: 900),
        RaceGroup(rank: "GS_4th_1422", subgroup: "GS_4th_1422", startNumber: 1000),
        RaceGroup(rank: "GS_4th_1797", subgroup: "GS_4th_1797", startNumber: 1100),
        RaceGroup(rank: "GS_5th_1476", subgroup: "GS_5th_1476", startNumber: 1200),
        RaceGroup(rank: "Outlaw", subgroup: "Test Race", startNumber: 1),
    ]
}

enum PhotoKind: String, Identifiable {
    case racer, car
    var id: String { rawValue }
}

struct EventData: Codable {
    var eventName = "Pinewood Derby"
    var groups = RaceGroup.defaults
    var maxWeightOz = 5.0
    /// Windows folder on the GPRM PC where exported images will be copied, used for the ImageFile column.
    var imageFolderOnPC = #"C:\Users\Pack352\Documents\Lisano Enterprises\GrandPrix Race Manager\Images"#
    var racers: [Racer] = []
}

// View-local state. Kept in ObservableObjects instead of @State because the
// Command Line Tools ship without the SwiftUI macro plugin that @State needs.

final class GroupsState: ObservableObject {
    @Published var renumberGroup: RaceGroup.ID?
}
