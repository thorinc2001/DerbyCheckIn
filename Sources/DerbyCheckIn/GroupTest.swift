import DerbyCore
import DerbyKit
import Foundation

/// `DerbyCheckIn --grouptest <roster.csv> <old event.json> <scratch folder>` checks race-group
/// editing and numbering against a real roster, printing PASS/FAIL for each check.
@MainActor
enum GroupTest {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--grouptest"), args.count > i + 3 else { return }
        let folder = URL(fileURLWithPath: args[i + 3], isDirectory: true).appendingPathComponent("data")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: args[i + 2]), to: folder.appendingPathComponent("event.json"))
        let store = Store(folder: folder)
        var failed = 0
        func check(_ name: String, _ ok: Bool) {
            print((ok ? "PASS " : "FAIL ") + name)
            if !ok { failed += 1 }
        }
        func group(_ rank: String) -> RaceGroup { store.data.groups.first { $0.rank == rank }! }

        check("old saved file loads", store.message == nil && store.data.groups.count == 11)
        check("old groups get start numbers", group("CS_3_Bears").startNumber == 400 && group("Outlaw").startNumber == 1)

        store.data.racers = []  // the copied event may hold cars that clash with the roster
        let before = store.data.racers.count
        _ = store.data.importRoster(text: (try? String(contentsOfFile: args[i + 1], encoding: .utf8)) ?? "")
        check("roster imports 91 cars", store.data.racers.count == before + 91)

        var bear = Racer(); bear.rank = "CS_3_Bears"
        check("next Bears number is 411 (400-410 taken)", store.data.nextCarNumber(for: bear) == 411)
        var outlaw = Racer(); outlaw.rank = "Outlaw"
        check("next Outlaw number is 6 (1-5 taken)", store.data.nextCarNumber(for: outlaw) == 6)

        let lions = group("CS_K_Lions")
        store.data.setStartNumber(lions.id, to: 150)
        var lion = Racer(); lion.rank = "CS_K_Lions"
        check("new start number used for next car", store.data.nextCarNumber(for: lion) == 150)

        store.settingsMessage = store.data.renumber(lions.id, onlyUnnumbered: false)
        let lionNumbers = store.data.racers.filter { $0.rank == "CS_K_Lions" }.map(\.carNumber).sorted()
        check("renumber gives Lions 150-157", lionNumbers == Array(150...157))
        check("renumber leaves no duplicates", store.data.exportProblems(store.data.racers.filter { $0.carNumber > 0 }).isEmpty)

        store.settingsMessage = store.data.renameRank(lions.id, to: "CS_K_Lion_Cubs")
        check("renaming a Rank moves its cars", store.data.carCount(rank: "CS_K_Lion_Cubs") == 8 && store.data.carCount(rank: "CS_K_Lions") == 0)
        store.settingsMessage = store.data.renameRank(lions.id, to: "cs_3_bears")
        check("duplicate Rank is refused", group("CS_K_Lion_Cubs").id == lions.id && store.settingsMessage != nil)
        store.settingsMessage = nil

        store.data.renameSubgroup(lions.id, to: "Lion Cubs")
        check("renaming a Subgroup updates its cars", store.data.racers.filter { $0.rank == "CS_K_Lion_Cubs" }.allSatisfy { $0.subgroup == "Lion Cubs" })

        store.settingsMessage = store.data.deleteGroup(group("CS_3_Bears").id)
        check("group with cars can't be deleted", store.data.groups.contains { $0.rank == "CS_3_Bears" } && store.settingsMessage != nil)

        store.data.addGroup()
        let added = store.data.groups.last!
        check("new group starts at next free hundred (1300)", added.startNumber == 1300)
        store.settingsMessage = store.data.deleteGroup(added.id)
        check("empty group can be deleted", !store.data.groups.contains { $0.id == added.id })

        store.data.setStartNumber(group("CS_2_Wolves").id, to: 400)
        check("matching start numbers are flagged", store.data.startNumberProblem(group("CS_2_Wolves")) != nil)

        store.save()
        let reloaded = Store(folder: folder)
        check("start numbers and names survive a reload",
              reloaded.data.groups.first { $0.rank == "CS_K_Lion_Cubs" }?.startNumber == 150
                && reloaded.data.groups.first { $0.rank == "CS_K_Lion_Cubs" }?.subgroup == "Lion Cubs")

        print(failed == 0 ? "All checks passed" : "\(failed) checks failed")
        exit(failed == 0 ? 0 : 1)
    }
}
