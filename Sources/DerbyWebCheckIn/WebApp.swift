import DerbyCore
import DerbyKit
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import SystemConfiguration

@main
struct DerbyWebCheckInApp: App {
    @StateObject private var store: Store
    @StateObject private var server: ServerController

    init() {
        // Its own folder in Documents, so it never edits the desktop app's event by accident.
        Store.appFolderName = "Derby Web Check In"
        let args = CommandLine.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
        }
        // --data-folder and --port are for testing; they are not remembered.
        let store = Store(folder: value(after: "--data-folder").map { URL(fileURLWithPath: $0, isDirectory: true) })
        _store = StateObject(wrappedValue: store)
        _server = StateObject(wrappedValue: ServerController(store: store, portOverride: value(after: "--port").flatMap { Int($0) }))
    }

    var body: some Scene {
        Window("Derby Web Check In", id: "main") {
            HostView()
                .environmentObject(store)
                .environmentObject(server)
                .frame(minWidth: 640, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open Check-In Page in Browser") { server.openInBrowser() }
                    .keyboardShortcut("o")
                Divider()
                Button("Import Roster…") { store.importRoster() }
                    .keyboardShortcut("i")
                Button("Export Checked-In Racers for GPRM…") { store.export(checkedInOnly: true) }
                    .keyboardShortcut("e")
                Button("Export All Racers for GPRM…") { store.export(checkedInOnly: false) }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Show Data Folder in Finder") { store.showDataFolder() }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
        .windowResizability(.contentSize)
    }
}

/// Runs the web server and keeps track of the addresses other computers can use.
@MainActor
final class ServerController: ObservableObject {
    @Published private(set) var running = false
    @Published private(set) var problem: String?
    @Published var port: Int
    @Published private(set) var addresses: [NetworkAddress] = []
    @Published private(set) var hostName = ""

    private let api: WebAPI
    private var server: HTTPServer!
    private var activity: NSObjectProtocol?
    private var refresh: Timer?
    private let remembersPort: Bool

    struct NetworkAddress: Hashable {
        let ip: String
        let interface: String
        /// 169.254.x.x: the Mac gave itself an address because no router handed one out.
        var isSelfAssigned: Bool { ip.hasPrefix("169.254.") }
    }

    init(store: Store, portOverride: Int?) {
        remembersPort = portOverride == nil
        let saved = UserDefaults.standard.integer(forKey: "port")
        port = portOverride ?? (saved > 0 ? saved : 8080)
        api = WebAPI(store: store)
        let api = self.api
        server = HTTPServer { @Sendable request in await api.handle(request) }
        server.onStateChange = { [weak self] problem in
            guard let self else { return }
            self.problem = problem
            self.running = problem == nil
            if problem != nil { self.endActivity() }
        }
        refreshAddresses()
        refresh = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAddresses() }
        }
        start()
    }

    var urls: [URL] {
        var hosts = addresses.map(\.ip)
        if !hostName.isEmpty { hosts.insert(hostName, at: 0) }
        return hosts.compactMap { URL(string: "http://\($0):\(port)") }
    }

    /// The address to put in the QR code: a real network address beats the .local name,
    /// which some phones can't resolve.
    var primaryURL: URL? {
        let best = addresses.first { !$0.isSelfAssigned } ?? addresses.first
        return best.flatMap { URL(string: "http://\($0.ip):\(port)") } ?? urls.first
    }

    func start() {
        guard (1...65535).contains(port) else {
            problem = "Choose a port between 1 and 65535."
            return
        }
        if remembersPort { UserDefaults.standard.set(port, forKey: "port") }
        problem = nil
        do {
            try server.start(port: UInt16(port), serviceName: "Derby Web Check In")
            // Keep the Mac awake while computers depend on it.
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .userInitiated], reason: "Serving Derby Web Check In")
            }
        } catch {
            problem = error.localizedDescription
            running = false
        }
    }

    func stop() {
        server.stop()
        running = false
        endActivity()
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    func openInBrowser() {
        if let url = URL(string: "http://localhost:\(port)") { NSWorkspace.shared.open(url) }
    }

    func refreshAddresses() {
        let found = Self.currentAddresses()
        if found != addresses { addresses = found }
        let name = (SCDynamicStoreCopyLocalHostName(nil) as String?).map { "\($0).local" } ?? ""
        if name != hostName { hostName = name }
    }

    /// IPv4 addresses on Wi-Fi, Ethernet and Internet Sharing interfaces.
    private static func currentAddresses() -> [NetworkAddress] {
        var result: [NetworkAddress] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for item in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(item.pointee.ifa_flags)
            guard let addr = item.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let interface = String(cString: item.pointee.ifa_name)
            guard interface.hasPrefix("en") || interface.hasPrefix("bridge") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                result.append(NetworkAddress(ip: ip, interface: interface))
            }
        }
        return result.sorted { ($0.isSelfAssigned ? 1 : 0, $0.interface) < ($1.isSelfAssigned ? 1 : 0, $1.interface) }
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: output.extent.width / 2, height: output.extent.height / 2))
    }
}
