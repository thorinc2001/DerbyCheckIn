import DerbyCore
import DerbyKit
import AppKit
import SwiftUI

/// The window on the host Mac: how to connect, what's been checked in, and server controls.
struct HostView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var server: ServerController
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Derby Web Check In").font(.title2.bold())
                        Text(store.data.eventName).foregroundStyle(.secondary)
                    }
                    Spacer()
                    status
                }
            }

            if server.running {
                connectSection
            }

            Section("Check-in so far") {
                let racers = store.data.racers
                LabeledContent("Cars") { Text("\(racers.count)").monospacedDigit() }
                LabeledContent("Checked in") { Text("\(racers.filter(\.isCheckedIn).count)").monospacedDigit() }
                LabeledContent("Passed inspection") { Text("\(racers.filter { $0.inspection.passed == true }.count)").monospacedDigit() }
                LabeledContent("Saved in") {
                    Text(store.folder.path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }
                HStack {
                    Button("Show in Finder") { store.showDataFolder() }
                    Button("Settings…") { openSettings() }
                    Spacer()
                    Button("Import Roster…") { store.importRoster() }
                    Menu("Export for GPRM") {
                        Button("Export Checked-In Racers…") { store.export(checkedInOnly: true) }
                        Button("Export All Racers…") { store.export(checkedInOnly: false) }
                    }
                    .fixedSize()
                }
            }

            Section {
                LabeledContent("Port") {
                    HStack {
                        TextField("Port", value: $server.port, format: .number.grouping(.never))
                            .labelsHidden()
                            .frame(width: 80)
                            .disabled(server.running)
                        if server.running {
                            Button("Stop Server") { server.stop() }
                        } else {
                            Button("Start Server") { server.start() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                if let problem = server.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            } header: {
                Text("Server")
            } footer: {
                Text("This Mac stays awake while the server runs. The first time, macOS may ask whether to allow incoming network connections: click Allow.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("No network where you race?") {
                Text(networkHelp)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .alert("Derby Web Check In", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }

    @ViewBuilder private var status: some View {
        if server.running {
            Label("Running", systemImage: "circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
        } else {
            Label("Stopped", systemImage: "circle.fill")
                .foregroundStyle(.secondary)
                .font(.headline)
        }
    }

    @ViewBuilder private var connectSection: some View {
        Section {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("On each PC, Mac, tablet or phone on the same network, open a web browser and go to:")
                        .fixedSize(horizontal: false, vertical: true)
                    if server.urls.isEmpty {
                        Label("This Mac isn't connected to a network yet. Join Wi-Fi or plug in Ethernet.",
                              systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                    ForEach(server.urls, id: \.self) { url in
                        HStack {
                            Text(url.absoluteString)
                                .font(.system(.title3, design: .monospaced).weight(.semibold))
                                .textSelection(.enabled)
                            Spacer()
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                            }
                        }
                    }
                    if server.addresses.contains(where: \.isSelfAssigned) {
                        Text("A 169.254 address means no router is giving out addresses. It still works for computers connected straight to this Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button("Open on This Mac", systemImage: "safari") { server.openInBrowser() }
                }
                if let url = server.primaryURL, let qr = QRCode.image(for: url.absoluteString) {
                    VStack(spacing: 4) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 150, height: 150)
                            .padding(6)
                            .background(.white, in: RoundedRectangle(cornerRadius: 8))
                        Text("Scan with a phone or tablet").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Connect other computers")
        }
    }

    private var networkHelp: String {
        """
        Every computer just needs to be on the same network as this Mac; no internet is needed.
        • Easiest: bring a small travel Wi-Fi router, plug it in, and join its Wi-Fi from this Mac and every check-in computer.
        • Or plug computers into the same network switch with Ethernet cables.
        • A phone hotspot also works if every computer joins it, though some hotspots keep devices apart.
        The addresses above update automatically when this Mac joins a different network.
        """
    }
}
