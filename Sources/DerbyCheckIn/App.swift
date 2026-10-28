import DerbyCore
import DerbyKit
import SwiftUI

@main
struct DerbyCheckInApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup("Derby Check-In") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 640)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Racer") { store.addRacer() }
                    .keyboardShortcut("n")
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Import Roster…") { store.importRoster() }
                    .keyboardShortcut("i")
                Button("Export Checked-In Racers for GPRM…") { store.export(checkedInOnly: true) }
                    .keyboardShortcut("e")
                Button("Export All Racers for GPRM…") { store.export(checkedInOnly: false) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                OpenGroupsButton()
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Show Data Folder in Finder") { store.showDataFolder() }
                    .help(store.folder.path)
            }
        }


        Settings {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}


enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case waiting = "Not Checked In"
    case checkedIn = "Checked In"
    case needsInspection = "Needs Inspection"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @Environment(\.undoManager) private var undoManager
    @State private var search = ""
    @State private var groupFilter = ""
    @State private var status = StatusFilter.all

    private var filtered: [Racer] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.data.racers
            .filter { groupFilter.isEmpty || $0.rank == groupFilter }
            .filter {
                switch status {
                case .all: true
                case .waiting: !$0.isCheckedIn
                case .checkedIn: $0.isCheckedIn
                case .needsInspection: $0.inspection.passed != true
                }
            }
            .filter { q.isEmpty || $0.fullName.lowercased().contains(q) || String($0.carNumber) == q || $0.carName.lowercased().contains(q) }
            .sorted(by: Racer.displayOrder)
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $store.selection) { racer in
                RacerRow(racer: racer).tag(racer.id)
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Name or car #")
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    Picker("Group", selection: $groupFilter) {
                        Text("All groups").tag("")
                        ForEach(store.data.groups) { Text($0.name).tag($0.rank) }
                    }
                    Picker("Show", selection: $status) {
                        ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .labelsHidden()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            .safeAreaInset(edge: .bottom) {
                let checked = store.data.racers.filter(\.isCheckedIn).count
                Text("\(checked) of \(store.data.racers.count) checked in")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            if let id = store.selection, store.data.racers.contains(where: { $0.id == id }) {
                RacerDetailView(racer: store.binding(id))
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Racer Selected", systemImage: "car.side")
                } description: {
                    Text("Pick a racer on the left, add a new one, or import a pre-registration roster.")
                } actions: {
                    Button("New Racer") { store.addRacer(rank: groupFilter) }
                    Button("Import Roster…") { store.importRoster() }
                }
            }
        }
        .navigationTitle(store.data.eventName)
        // Every change to the event goes on this window's Undo stack (Edit › Undo, ⌘Z).
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { _, manager in store.undoManager = manager }
        .toolbar {
            ToolbarItemGroup {
                OpenGroupsButton()
                Button("New Racer", systemImage: "plus") { store.addRacer(rank: groupFilter) }
                Menu("Export", systemImage: "square.and.arrow.up") {
                    Button("Export Checked-In Racers for GPRM…") { store.export(checkedInOnly: true) }
                    Button("Export All Racers for GPRM…") { store.export(checkedInOnly: false) }
                }
            }
        }
        .alert("Derby Check-In", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}

struct RacerRow: View {
    let racer: Racer

    var body: some View {
        HStack(spacing: 10) {
            Text(racer.carNumber > 0 ? "#\(racer.carNumber)" : "—")
                .font(.system(.body, design: .rounded).monospacedDigit().bold())
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(racer.fullName.isEmpty ? "New Racer" : racer.fullName)
                Text([racer.groupName.isEmpty ? "No group" : racer.groupName, racer.carName]
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if racer.exclude {
                Image(systemName: "nosign").foregroundStyle(.secondary).help("Excluded from racing")
            }
            if racer.inspection.passed == false {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red).help("Failed inspection")
            }
            if racer.isCheckedIn {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Checked in")
            } else {
                Image(systemName: "circle").foregroundStyle(.tertiary).help("Not checked in")
            }
        }
        .padding(.vertical, 2)
    }
}
