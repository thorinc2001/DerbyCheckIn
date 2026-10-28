import Foundation

// The check-in rules, written once. The Mac app and the web server both call these,
// so they can't drift apart.

// MARK: Checks

public extension EventData {
    /// Next free number in the rank's own series (e.g. Bears 400, 401, …).
    /// Uses the group's start number when it has one; otherwise continues after the
    /// group's highest car, or starts at the next free hundred.
    func nextCarNumber(for racer: Racer) -> Int {
        let others = racers.filter { $0.id != racer.id }
        let used = Set(others.map(\.carNumber))
        var n: Int
        if let start = groups.first(where: { $0.rank == racer.rank })?.startNumber, start > 0 {
            n = start
        } else if let max = others.filter({ $0.rank == racer.rank && $0.carNumber > 0 }).map(\.carNumber).max() {
            n = max + 1
        } else {
            n = ((others.map(\.carNumber).max() ?? 0) / 100 + 1) * 100
        }
        while used.contains(n) { n += 1 }
        return n
    }

    func carNumberProblem(for racer: Racer) -> String? {
        if racer.carNumber <= 0 { return "Needs a car number (a whole number above 0)." }
        if let other = racers.first(where: { $0.id != racer.id && $0.carNumber == racer.carNumber }) {
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

    /// Shown in the Race Groups editor.
    func carCount(rank: String) -> Int {
        racers.filter { $0.rank == rank }.count
    }

    /// Why a group's start number may cause trouble, or nil.
    func startNumberProblem(_ group: RaceGroup) -> String? {
        guard group.startNumber > 0 else { return nil }
        if let other = groups.first(where: { $0.id != group.id && $0.startNumber == group.startNumber }) {
            return "Same start as \(other.subgroup.isEmpty ? other.rank : other.subgroup)"
        }
        return nil
    }
}

// MARK: Editing racers

public extension EventData {
    /// The automatic follow-ups to a racer edit: trims the car name, ticks the weight check,
    /// marks the car passed once every check is ticked, and fills in the group name and the
    /// next car number when a group is chosen.
    func applyingEditRules(_ edited: Racer, was old: Racer) -> Racer {
        var racer = edited
        if racer.carName.count > maxCarNameLength {
            racer.carName = String(racer.carName.prefix(maxCarNameLength))
        }
        if racer.weightOz != old.weightOz {
            racer.inspection.weightOK = racer.weightOz > 0 && racer.weightOz <= maxWeightOz
        }
        if racer.inspection.allChecked && !old.inspection.allChecked && racer.inspection.passed == nil {
            racer.inspection.passed = true
        }
        if racer.rank != old.rank {
            racer.subgroup = groups.first { $0.rank == racer.rank }?.subgroup ?? ""
            if racer.carNumber <= 0 && !racer.rank.isEmpty {
                racer.carNumber = nextCarNumber(for: racer)
            }
        }
        return racer
    }

    /// Adds a racer, in `rank`'s group with its next number when that group exists.
    @discardableResult
    mutating func addRacer(rank: String = "") -> Racer {
        var racer = Racer()
        if let group = groups.first(where: { $0.rank == rank }) {
            racer.rank = group.rank
            racer.subgroup = group.subgroup
            racer.carNumber = nextCarNumber(for: racer)
        }
        racers.append(racer)
        return racer
    }

    /// Adds another car for the same racer (GPRM allows one racer several cars).
    @discardableResult
    mutating func addCar(for racer: Racer) -> Racer {
        var car = Racer()
        car.firstName = racer.firstName
        car.lastName = racer.lastName
        car.rank = racer.rank
        car.subgroup = racer.subgroup
        car.carNumber = nextCarNumber(for: car)
        racers.append(car)
        return car
    }
}

// MARK: Race groups
// Each returns a message for the user when it refuses or reports something, otherwise nil.

public extension EventData {
    mutating func addGroup() {
        let highest = max(groups.map(\.startNumber).max() ?? 0, racers.map(\.carNumber).max() ?? 0)
        var n = 1
        while groups.contains(where: { $0.rank == "New_Group_\(n)" }) { n += 1 }
        groups.append(RaceGroup(rank: "New_Group_\(n)", subgroup: "New Group \(n)",
                                startNumber: (highest / 100 + 1) * 100))
    }

    /// Renames a group's Rank and moves its cars with it.
    mutating func renameRank(_ id: RaceGroup.ID, to newRank: String) -> String? {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return nil }
        let old = groups[i].rank
        let rank = newRank.trimmingCharacters(in: .whitespaces)
        guard rank != old else { return nil }
        if rank.isEmpty { return "A group's Rank can't be blank." }
        if groups.contains(where: { $0.id != id && $0.rank.caseInsensitiveCompare(rank) == .orderedSame }) {
            return "There is already a group with the Rank “\(rank)”."
        }
        groups[i].rank = rank
        for j in racers.indices where racers[j].rank == old {
            racers[j].rank = rank
        }
        return nil
    }

    /// Changes a group's Subgroup (display name) and updates its cars.
    mutating func renameSubgroup(_ id: RaceGroup.ID, to newName: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let rank = groups[i].rank
        let name = newName.trimmingCharacters(in: .whitespaces)
        groups[i].subgroup = name.isEmpty ? rank : name
        for j in racers.indices where racers[j].rank == rank {
            racers[j].subgroup = groups[i].subgroup
        }
    }

    mutating func setStartNumber(_ id: RaceGroup.ID, to start: Int) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].startNumber = max(0, start)
    }

    mutating func deleteGroup(_ id: RaceGroup.ID) -> String? {
        guard let group = groups.first(where: { $0.id == id }) else { return nil }
        let count = carCount(rank: group.rank)
        guard count == 0 else {
            return "\(count) car\(count == 1 ? " is" : "s are") in \(group.name). Move them to another group first."
        }
        groups.removeAll { $0.id == id }
        return nil
    }

    /// Gives every car in the group a number from its start, in name order.
    /// With `onlyUnnumbered`, cars that already have a number keep it.
    mutating func renumber(_ id: RaceGroup.ID, onlyUnnumbered: Bool) -> String? {
        guard let group = groups.first(where: { $0.id == id }), group.startNumber > 0 else { return nil }
        let targets = racers.indices
            .filter { racers[$0].rank == group.rank && (!onlyUnnumbered || racers[$0].carNumber <= 0) }
            .sorted { Racer.displayOrder(racers[$0], racers[$1]) }
        let targetIDs = Set(targets.map { racers[$0].id })
        var used = Set(racers.filter { !targetIDs.contains($0.id) }.map(\.carNumber))
        var n = group.startNumber
        for i in targets {
            while used.contains(n) { n += 1 }
            racers[i].carNumber = n
            used.insert(n)
        }
        return "Numbered \(targets.count) car\(targets.count == 1 ? "" : "s") in \(group.name) starting at \(group.startNumber)."
    }

    /// Groups saved before start numbers existed get the pack's usual series.
    mutating func fillDefaultStartNumbers() {
        for i in groups.indices where groups[i].startNumber == 0 {
            groups[i].startNumber = RaceGroup.defaults.first { $0.rank == groups[i].rank }?.startNumber ?? 0
        }
    }
}
