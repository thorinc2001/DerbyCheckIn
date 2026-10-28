import Foundation

/// GPRM truncates car names longer than this.
public let maxCarNameLength = 20

public struct Racer: Identifiable, Codable, Hashable, Sendable {
    public var id = UUID()
    /// 0 means "not assigned yet". GPRM requires a positive, unique whole number.
    public var carNumber = 0
    public var firstName = ""
    public var lastName = ""
    /// GPRM "Rank": the race group, e.g. CS_3_Bears.
    public var rank = ""
    /// GPRM "Subgroup": the group's display name, e.g. Bears.
    public var subgroup = ""
    public var carName = ""
    /// 0 means "not weighed yet". Used for inspection only; GPRM's roster has no weight column.
    public var weightOz = 0.0
    public var inspection = Inspection()
    public var notes = ""
    /// File names inside the event's Photos folder.
    public var racerPhoto: String?
    public var carPhoto: String?
    public var checkedInAt: Date?
    // GPRM flags, carried through import and export.
    public var exclude = false
    public var finalist = false
    public var grandFinalist = false
    public var grandTurtle = false

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public var fullName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    public var groupName: String { subgroup.isEmpty ? rank : subgroup }

    public var isCheckedIn: Bool { checkedInAt != nil }

    /// List and export order: last name, first name, then car number.
    public static func displayOrder(_ a: Racer, _ b: Racer) -> Bool {
        (a.lastName.lowercased(), a.firstName.lowercased(), a.carNumber)
            < (b.lastName.lowercased(), b.firstName.lowercased(), b.carNumber)
    }
}

public struct Inspection: Codable, Hashable, Sendable {
    public var weightOK = false
    public var dimensionsOK = false
    public var clearanceOK = false
    public var wheelsAxlesOK = false
    public var noLooseParts = false
    /// nil = not inspected yet.
    public var passed: Bool?

    public init() {}

    public var allChecked: Bool {
        weightOK && dimensionsOK && clearanceOK && wheelsAxlesOK && noLooseParts
    }
}

/// A GPRM race group: a Rank and the Subgroup name shown for it.
public struct RaceGroup: Codable, Hashable, Identifiable, Sendable {
    public var id = UUID()
    public var rank: String
    public var subgroup: String
    /// First car number for this group's series (e.g. 400 for Bears). 0 = no set start.
    public var startNumber = 0

    public var name: String { subgroup.isEmpty || subgroup == rank ? rank : "\(subgroup) (\(rank))" }

    public init(rank: String, subgroup: String, startNumber: Int = 0) {
        self.rank = rank
        self.subgroup = subgroup
        self.startNumber = startNumber
    }

    // Groups saved before id and startNumber existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        rank = try c.decode(String.self, forKey: .rank)
        subgroup = try c.decodeIfPresent(String.self, forKey: .subgroup) ?? ""
        startNumber = try c.decodeIfPresent(Int.self, forKey: .startNumber) ?? 0
    }

    /// The pack's groups and number series, from its GPRM roster.
    public static let defaults = [
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

public enum PhotoKind: String, Identifiable, Sendable {
    case racer, car
    public var id: String { rawValue }
}

public struct EventData: Codable, Sendable {
    public var eventName = "Pinewood Derby"
    public var groups = RaceGroup.defaults
    public var maxWeightOz = 5.0
    /// Windows folder on the GPRM PC where exported images will be copied, used for the ImageFile column.
    public var imageFolderOnPC = #"C:\Users\Pack352\Documents\Lisano Enterprises\GrandPrix Race Manager\Images"#
    public var racers: [Racer] = []

    public init() {}
}
