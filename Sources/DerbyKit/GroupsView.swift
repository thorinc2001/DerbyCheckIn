import DerbyCore
import SwiftUI

/// Edits the race groups: GPRM Rank, Subgroup name, and the first car number of each series.
struct GroupsView: View {
    @EnvironmentObject var store: Store
    @StateObject private var ui = GroupsState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Rank (GPRM)").frame(width: GroupRow.rankWidth, alignment: .leading)
                Text("Subgroup name").frame(maxWidth: .infinity, alignment: .leading)
                Text("Starts at").frame(width: GroupRow.startWidth, alignment: .leading)
                Text("Cars").frame(width: GroupRow.countWidth, alignment: .trailing)
                Color.clear.frame(width: GroupRow.menuWidth, height: 1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            List {
                ForEach(store.data.groups) { group in
                    GroupRow(group: group) { ui.renumberGroup = group.id }
                }
                .onMove { store.data.groups.move(fromOffsets: $0, toOffset: $1) }
            }

            Divider()
            HStack {
                Button("Add Group", systemImage: "plus") { store.data.addGroup() }
                Spacer()
                Text("Press Return to save a change. Drag rows to reorder. Next Available fills each group's numbers from its start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .padding(12)
        }
        .frame(minWidth: 680, minHeight: 400)
        .confirmationDialog(
            "Renumber every car in \(renumberTarget?.name ?? "this group")?",
            isPresented: Binding(get: { ui.renumberGroup != nil }, set: { if !$0 { ui.renumberGroup = nil } }),
            presenting: renumberTarget
        ) { group in
            Button("Renumber \(store.data.carCount(rank: group.rank)) Cars") {
                store.settingsMessage = store.data.renumber(group.id, onlyUnnumbered: false)
            }
        } message: { group in
            Text("Cars get new numbers from \(group.startNumber) up, in last-name order. Any car already labelled will need a new number label.")
        }
    }

    private var renumberTarget: RaceGroup? {
        store.data.groups.first { $0.id == ui.renumberGroup }
    }
}

struct GroupRow: View {
    static let rankWidth: CGFloat = 170
    static let startWidth: CGFloat = 80
    static let countWidth: CGFloat = 40
    static let menuWidth: CGFloat = 30

    @EnvironmentObject var store: Store
    let group: RaceGroup
    let onRenumberAll: () -> Void

    var body: some View {
        let count = store.data.carCount(rank: group.rank)
        let canNumber = group.startNumber > 0 && count > 0
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                TextField("Rank", value: Binding(get: { group.rank }, set: { store.settingsMessage = store.data.renameRank(group.id, to: $0) }),
                          format: PlainText())
                    .frame(width: Self.rankWidth)
                TextField("Subgroup", value: Binding(get: { group.subgroup }, set: { store.data.renameSubgroup(group.id, to: $0) }),
                          format: PlainText())
                TextField("Start", value: Binding(get: { group.startNumber }, set: { store.data.setStartNumber(group.id, to: $0) }),
                          format: .number.grouping(.never))
                    .frame(width: Self.startWidth)
                Text("\(count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: Self.countWidth, alignment: .trailing)
                Menu {
                    Button("Number Cars Without a Number") { store.settingsMessage = store.data.renumber(group.id, onlyUnnumbered: true) }
                        .disabled(!canNumber)
                    Button("Renumber All Cars from \(group.startNumber)…", action: onRenumberAll)
                        .disabled(!canNumber)
                    Divider()
                    Button("Delete Group", role: .destructive) { store.settingsMessage = store.data.deleteGroup(group.id) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: Self.menuWidth)
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)

            if let problem = store.data.startNumberProblem(group) {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Lets a text field edit a String but only commit it on Return or when focus leaves,
/// so renaming a Rank doesn't move cars around on every keystroke.
struct PlainText: ParseableFormatStyle, ParseStrategy {
    var parseStrategy: PlainText { self }
    func format(_ value: String) -> String { value }
    func parse(_ value: String) throws -> String { value.trimmingCharacters(in: .whitespaces) }
}

/// View-local state, kept in an ObservableObject while the app builds without the @State macro.
final class GroupsState: ObservableObject {
    @Published var renumberGroup: RaceGroup.ID?
}
