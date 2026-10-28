import Foundation
import Testing
@testable import DerbyCore

@Suite("Car numbers and check-in")
struct NumberingTests {
    @Test func nextNumberFollowsTheGroupStart() {
        let event = importedSample()
        var bear = Racer(); bear.rank = "CS_3_Bears"
        #expect(event.nextCarNumber(for: bear) == 402, "400, 401 and 405 are taken")
        var outlaw = Racer(); outlaw.rank = "Outlaw"
        #expect(event.nextCarNumber(for: outlaw) == 3)
        var webelos = Racer(); webelos.rank = "CS_4_Webelos"
        #expect(event.nextCarNumber(for: webelos) == 500)
    }

    @Test func groupWithoutAStartUsesTheNextHundred() {
        var event = importedSample()
        event.groups.append(RaceGroup(rank: "Siblings", subgroup: "Siblings"))
        var sibling = Racer(); sibling.rank = "Siblings"
        #expect(event.nextCarNumber(for: sibling) == 1100, "the highest car is 1003")
    }

    @Test func duplicateNumbersAreFlagged() throws {
        var event = importedSample()
        var racer = event.addRacer(rank: "CS_3_Bears")
        racer.carNumber = 400
        #expect(event.carNumberProblem(for: racer) == "Car #400 is already used by Drew Diaz.")
        racer.carNumber = 0
        #expect(event.carNumberProblem(for: racer) == "Needs a car number (a whole number above 0).")
    }

    @Test func checkInNeedsNameGroupAndNumber() {
        let event = EventData()
        var racer = Racer()
        #expect(event.checkInBlocker(racer) == "Enter the racer's first and last name.")
        racer.firstName = "Pat"; racer.lastName = "Lee"
        #expect(event.checkInBlocker(racer) == "Choose a race group (rank).")
        racer.rank = "CS_3_Bears"
        #expect(event.checkInBlocker(racer)?.hasPrefix("Needs a car number") == true)
        racer.carNumber = 450
        #expect(event.checkInBlocker(racer) == nil)
    }

    @Test func exportProblemsListDuplicatesAndGaps() {
        var event = importedSample()
        let racer = event.addRacer()
        event.racers[0].carNumber = 400
        let problems = event.exportProblems(event.racers)
        #expect(problems.contains("A racer with no name is missing a first or last name."))
        #expect(problems.contains("A racer with no name has no car number."))
        #expect(problems.contains("Car #400 is used by Alex Avery, Drew Diaz."))
        #expect(event.exportProblems(event.racers.filter { $0.id != racer.id && $0.carNumber != 400 }).isEmpty)
    }

    @Test func addCarCopiesTheRacer() throws {
        var event = importedSample()
        let alex = try #require(event.racers.first { $0.carNumber == 405 })
        let car = event.addCar(for: alex)
        #expect(car.fullName == "Alex Avery" && car.rank == "CS_3_Bears" && car.subgroup == "Bears")
        #expect(car.carNumber == 402)
    }

    @Test func displayOrderIsLastFirstThenNumber() {
        let names = importedSample().racers.sorted(by: Racer.displayOrder).map { "\($0.lastName) \($0.carNumber)" }
        #expect(names.prefix(5) == ["Avery 405", "Brooks 1003", "Cole 1", "Cole 2", "Cole 300"])
    }
}

@Suite("Edit rules")
struct EditRuleTests {
    let event = importedSample()
    let old: Racer = {
        var r = Racer()
        r.firstName = "Pat"; r.lastName = "Lee"
        return r
    }()

    @Test func carNameIsCutTo20Characters() {
        var edited = old
        edited.carName = "A very long car name indeed"
        #expect(event.applyingEditRules(edited, was: old).carName == "A very long car name")
    }

    @Test(arguments: [(4.9, true), (5.0, true), (5.1, false), (0, false)])
    func weightTicksTheWeightCheck(weight: Double, ok: Bool) {
        var edited = old
        edited.weightOz = weight
        #expect(event.applyingEditRules(edited, was: old).inspection.weightOK == ok)
    }

    @Test func tickingEveryCheckPassesTheCar() {
        var before = old
        before.inspection.weightOK = true
        before.inspection.dimensionsOK = true
        before.inspection.clearanceOK = true
        before.inspection.wheelsAxlesOK = true
        var edited = before
        edited.inspection.noLooseParts = true
        #expect(event.applyingEditRules(edited, was: before).inspection.passed == true)
        edited.inspection.passed = false
        #expect(event.applyingEditRules(edited, was: before).inspection.passed == false, "a failed car stays failed")
    }

    @Test func weighingCanCompleteTheChecks() {
        var before = old
        before.inspection.dimensionsOK = true
        before.inspection.clearanceOK = true
        before.inspection.wheelsAxlesOK = true
        before.inspection.noLooseParts = true
        var edited = before
        edited.weightOz = 4.8
        let result = event.applyingEditRules(edited, was: before)
        #expect(result.inspection.weightOK && result.inspection.passed == true)
    }

    @Test func choosingAGroupFillsNameAndNumber() {
        var edited = old
        edited.rank = "CS_3_Bears"
        let result = event.applyingEditRules(edited, was: old)
        #expect(result.subgroup == "Bears")
        #expect(result.carNumber == 402)
    }

    @Test func changingGroupKeepsAnExistingNumber() {
        var before = old
        before.rank = "CS_3_Bears"; before.carNumber = 450
        var edited = before
        edited.rank = "CS_2_Wolves"
        let result = event.applyingEditRules(edited, was: before)
        #expect(result.subgroup == "Wolves" && result.carNumber == 450)
    }
}

@Suite("Race groups")
struct GroupTests {
    func group(_ event: EventData, _ rank: String) -> RaceGroup {
        event.groups.first { $0.rank == rank }!
    }

    @Test func renamingARankMovesItsCars() {
        var event = importedSample()
        let lions = group(event, "CS_K_Lions")
        #expect(event.renameRank(lions.id, to: "CS_K_Lion_Cubs") == nil)
        #expect(event.carCount(rank: "CS_K_Lion_Cubs") == 2 && event.carCount(rank: "CS_K_Lions") == 0)
    }

    @Test(arguments: ["cs_3_bears", "  "])
    func badRanksAreRefused(rank: String) {
        var event = importedSample()
        let lions = group(event, "CS_K_Lions")
        #expect(event.renameRank(lions.id, to: rank) != nil)
        #expect(group(event, "CS_K_Lions").id == lions.id)
    }

    @Test func renamingASubgroupUpdatesItsCars() {
        var event = importedSample()
        let lions = group(event, "CS_K_Lions")
        event.renameSubgroup(lions.id, to: "Lion Cubs")
        #expect(event.racers.filter { $0.rank == "CS_K_Lions" }.allSatisfy { $0.subgroup == "Lion Cubs" })
        event.renameSubgroup(lions.id, to: " ")
        #expect(group(event, "CS_K_Lions").subgroup == "CS_K_Lions", "a blank name falls back to the Rank")
    }

    @Test func startNumberCantBeNegative() {
        var event = EventData()
        event.setStartNumber(event.groups[0].id, to: -5)
        #expect(event.groups[0].startNumber == 0)
    }

    @Test func matchingStartsAreFlagged() {
        var event = EventData()
        let wolves = group(event, "CS_2_Wolves")
        event.setStartNumber(wolves.id, to: 400)
        #expect(event.startNumberProblem(group(event, "CS_2_Wolves")) == "Same start as Bears")
    }

    @Test func groupWithCarsCantBeDeleted() {
        var event = importedSample()
        #expect(event.deleteGroup(group(event, "CS_3_Bears").id) == "3 cars are in Bears (CS_3_Bears). Move them to another group first.")
        #expect(event.deleteGroup(group(event, "CS_4_Webelos").id) == nil)
        #expect(!event.groups.contains { $0.rank == "CS_4_Webelos" })
    }

    @Test func newGroupStartsAtTheNextFreeHundred() {
        var event = importedSample()
        event.addGroup()
        #expect(event.groups.last?.rank == "New_Group_1")
        #expect(event.groups.last?.startNumber == 1300, "the highest start is 1200")
    }

    @Test func renumberGivesNameOrderFromTheStart() {
        var event = importedSample()
        let bears = group(event, "CS_3_Bears")
        event.setStartNumber(bears.id, to: 450)
        #expect(event.renumber(bears.id, onlyUnnumbered: false) == "Numbered 3 cars in Bears (CS_3_Bears) starting at 450.")
        let numbers = event.racers.filter { $0.rank == "CS_3_Bears" }.sorted(by: Racer.displayOrder).map(\.carNumber)
        #expect(numbers == [450, 451, 452])
        #expect(event.exportProblems(event.racers).isEmpty)
    }

    @Test func renumberCanFillOnlyTheBlanks() {
        var event = importedSample()
        var blank = event.addRacer()
        blank.rank = "CS_3_Bears"
        event.racers[event.racers.count - 1] = blank
        _ = event.renumber(group(event, "CS_3_Bears").id, onlyUnnumbered: true)
        #expect(event.racers.last?.carNumber == 402)
        #expect(event.racers.first { $0.lastName == "Avery" }?.carNumber == 405, "numbered cars keep theirs")
    }

    @Test func oldSavedGroupsStillLoad() throws {
        let json = #"{"rank":"CS_3_Bears","subgroup":"Bears"}"#
        var event = EventData()
        event.groups = [try JSONDecoder().decode(RaceGroup.self, from: Data(json.utf8))]
        #expect(event.groups[0].startNumber == 0)
        event.fillDefaultStartNumbers()
        #expect(event.groups[0].startNumber == 400)
    }
}
