import DerbyCore
import AppKit
import SwiftUI

enum SettingsTab: String {
    case general, groups, storage
    static let key = "settingsTab"
}

/// The Settings window (⌘,): General, Race Groups and Storage tabs.
public struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage(SettingsTab.key) private var tab = SettingsTab.general.rawValue

    public init() {}

    public var body: some View {
        TabView(selection: $tab) {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general.rawValue)
            GroupsView()
                .tabItem { Label("Race Groups", systemImage: "list.number") }
                .tag(SettingsTab.groups.rawValue)
            StorageSettings()
                .tabItem { Label("Storage", systemImage: "externaldrive.badge.icloud") }
                .tag(SettingsTab.storage.rawValue)
        }
        .frame(width: 760, height: 560)
        .alert("Derby Check-In", isPresented: Binding(get: { store.settingsMessage != nil }, set: { if !$0 { store.settingsMessage = nil } })) {
            Button("OK") { store.settingsMessage = nil }
        } message: {
            Text(store.settingsMessage ?? "")
        }
    }
}

/// Opens Settings on the Race Groups tab.
public struct OpenGroupsButton: View {
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        Button("Edit Race Groups…", systemImage: "list.number") {
            UserDefaults.standard.set(SettingsTab.groups.rawValue, forKey: SettingsTab.key)
            openSettings()
        }
    }
}

struct GeneralSettings: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Form {
            TextField("Event name", text: $store.data.eventName)
            TextField("Maximum car weight (oz)", value: $store.data.maxWeightOz, format: .number)

            Section {
                TextField("Image folder on GPRM PC", text: $store.data.imageFolderOnPC,
                          prompt: Text(#"C:\Derby\Images"#))
            } footer: {
                Text("Where you will copy the export's Images folder on the Windows PC. Used for the ImageFile column; leave blank to leave ImageFile empty.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Storage

/// A OneDrive or Google Drive folder synced to this Mac by its desktop app.
public struct CloudFolder: Identifiable, Hashable {
    public enum Service { case oneDrive, googleDrive }
    public let service: Service
    public let name: String
    public let url: URL
    public var id: URL { url }

    /// Finds synced folders. Both apps keep them in ~/Library/CloudStorage on current macOS;
    /// older versions used ~/OneDrive or ~/Google Drive.
    public static func detect(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CloudFolder] {
        let fm = FileManager.default
        var found: [CloudFolder] = []
        let storage = home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
        let items = (try? fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)) ?? []
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let n = item.lastPathComponent
            if n.hasPrefix("OneDrive") {
                let account = n.dropFirst("OneDrive".count).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                found.append(CloudFolder(service: .oneDrive, name: account.isEmpty ? "OneDrive" : "OneDrive – \(account)", url: item))
            } else if n.hasPrefix("GoogleDrive") {
                let account = n.dropFirst("GoogleDrive".count).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
                let myDrive = item.appendingPathComponent("My Drive", isDirectory: true)
                found.append(CloudFolder(service: .googleDrive,
                                         name: account.isEmpty ? "Google Drive" : "Google Drive (\(account))",
                                         url: fm.fileExists(atPath: myDrive.path) ? myDrive : item))
            }
        }
        for (legacy, service, name) in [("OneDrive", Service.oneDrive, "OneDrive"), ("Google Drive", .googleDrive, "Google Drive")] {
            let url = home.appendingPathComponent(legacy, isDirectory: true)
            if fm.fileExists(atPath: url.path), !found.contains(where: { $0.service == service }) {
                found.append(CloudFolder(service: service, name: name, url: url))
            }
        }
        return found
    }

    /// The service a data folder lives in, if any.
    public static func service(of folder: URL, in clouds: [CloudFolder]) -> CloudFolder? {
        clouds.first { folder.standardizedFileURL.path.hasPrefix($0.url.standardizedFileURL.path) }
    }
}

final class StorageState: ObservableObject {
    @Published var clouds: [CloudFolder] = []
    /// A chosen folder that already holds an event, waiting for the user to decide.
    @Published var pending: URL?
    @Published var pendingCount = 0
}

struct StorageSettings: View {
    @EnvironmentObject var store: Store
    @StateObject private var ui = StorageState()

    var body: some View {
        Form {
            Section("Where your event and photos are saved") {
                LabeledContent("Folder") {
                    Text(store.folder.path)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(3)
                }
                LabeledContent("Kind") {
                    if let cloud = CloudFolder.service(of: store.folder, in: ui.clouds) {
                        Label("\(cloud.name) – syncs to the cloud", systemImage: "icloud")
                    } else {
                        Label("This Mac only", systemImage: "desktopcomputer")
                    }
                }
                HStack {
                    Button("Show in Finder") { store.showDataFolder() }
                    Spacer()
                    Button("Choose Another Folder…", action: chooseFolder)
                    Button("Move Back to Documents") { pick(Store.defaultFolder) }
                        .disabled(store.folder.standardizedFileURL == Store.defaultFolder.standardizedFileURL)
                }
            }

            Section {
                if ui.clouds.isEmpty {
                    Text("No OneDrive or Google Drive folder was found on this Mac. Install OneDrive or Google Drive for desktop, sign in, then click Look Again.")
                        .foregroundStyle(.secondary)
                }
                ForEach(ui.clouds) { cloud in
                    HStack {
                        Label(cloud.name, systemImage: cloud.service == .oneDrive ? "cloud" : "externaldrive.badge.icloud")
                        Spacer()
                        let target = cloud.url.appendingPathComponent("Derby Check-In", isDirectory: true)
                        if store.folder.standardizedFileURL == target.standardizedFileURL {
                            Label("In use", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Button("Use \(cloud.service == .oneDrive ? "OneDrive" : "Google Drive")") { pick(target) }
                        }
                    }
                }
                Button("Look Again", action: refresh)
            } header: {
                Text("OneDrive and Google Drive")
            } footer: {
                Text("Your event file and photos are saved in a “Derby Check-In” folder there, so they're backed up and other volunteers can open them. Use one Mac at a time for check-in: if two Macs save the same event at once, the last save wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
        .confirmationDialog(
            "That folder already has an event",
            isPresented: Binding(get: { ui.pending != nil }, set: { if !$0 { ui.pending = nil } })
        ) {
            Button("Open the Event in That Folder") {
                if let url = ui.pending { store.useDataFolder(url, bringCurrentEvent: false) }
            }
            Button("Replace It with This Mac's Event", role: .destructive) {
                if let url = ui.pending { store.useDataFolder(url, bringCurrentEvent: true) }
            }
        } message: {
            Text("The event there has \(ui.pendingCount) cars; the one open now has \(store.data.racers.count). Open it to pick up where someone else left off, or replace it with the one open now.")
        }
    }

    private func refresh() {
        ui.clouds = CloudFolder.detect()
    }

    private func pick(_ url: URL) {
        if let existing = Store.event(in: url) {
            ui.pendingCount = existing.racers.count
            ui.pending = url
        } else {
            store.useDataFolder(url, bringCurrentEvent: true)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder to save the event and photos in. A shared OneDrive or Google Drive folder works well."
        if let cloud = ui.clouds.first { panel.directoryURL = cloud.url }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pick(url)
    }
}
