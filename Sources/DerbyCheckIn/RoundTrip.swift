import DerbyCore
import DerbyKit
import Foundation

/// `DerbyCheckIn --roundtrip <roster.csv> <output folder>` imports a roster into a
/// throwaway event in the output folder, exports it back for GPRM, and exits.
/// Used to check the GPRM file format without touching the real event.
@MainActor
enum RoundTrip {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--roundtrip"), args.count > i + 2 else { return }
        let input = URL(fileURLWithPath: args[i + 1])
        let output = URL(fileURLWithPath: args[i + 2], isDirectory: true)
        do {
            let store = Store(folder: output.appendingPathComponent("data", isDirectory: true))
            let text = try String(contentsOf: input, encoding: .utf8)
            print(store.data.importRoster(text: text))
            print(store.data.importRoster(text: text))  // a second import must add nothing
            let problems = store.data.exportProblems(store.data.racers)
            if !problems.isEmpty { print("Export problems:\n" + problems.joined(separator: "\n")) }
            let dir = try store.writeExport(store.data.racers, into: output)
            print("Exported to \(dir.path)")
            exit(0)
        } catch {
            print("Round trip failed: \(error)")
            exit(1)
        }
    }
}
