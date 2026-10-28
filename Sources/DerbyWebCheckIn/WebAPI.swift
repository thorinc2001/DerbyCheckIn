import DerbyCore
import DerbyKit
import AppKit
import Combine
import Foundation

/// Answers the browser: serves the web app and a JSON API over the shared Store.
/// Every change returns the whole event so each computer stays in step.
@MainActor
final class WebAPI {
    let store: Store
    /// Goes up on every change; browsers poll it to know when to refresh.
    private(set) var version = 1
    private var watch: AnyCancellable?

    init(store: Store) {
        self.store = store
        watch = store.$data.dropFirst().sink { [weak self] _ in self?.version += 1 }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Where index.html, app.js and styles.css live: in the app bundle, or next to this
    /// source file when run straight from `swift run`.
    private static let webFolder: URL = {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Web"),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.html").path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Web")
    }()

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        let p = request.parts
        let m = request.method
        switch (m, p.first) {
        case ("GET", nil): return staticFile("index.html")
        case ("GET", "photos") where p.count == 2: return photo(p[1])
        case (_, "api"): return api(request, Array(p.dropFirst()))
        case ("GET", _) where p.count == 1: return staticFile(p[0])
        default: return .error("Not found", status: 404)
        }
    }

    // MARK: Files

    private func staticFile(_ name: String) -> HTTPResponse {
        let types = ["html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8",
                     "css": "text/css; charset=utf-8", "png": "image/png", "svg": "image/svg+xml"]
        guard !name.contains(".."), let type = types[(name as NSString).pathExtension],
              let data = try? Data(contentsOf: Self.webFolder.appendingPathComponent(name)) else {
            return .error("Not found", status: 404)
        }
        return .data(data, type: type)
    }

    private func photo(_ name: String) -> HTTPResponse {
        guard !name.contains("/"), !name.contains(".."),
              let data = try? Data(contentsOf: store.photoURL(name)) else {
            return .error("Not found", status: 404)
        }
        var response = HTTPResponse.data(data, type: "image/jpeg")
        response.headers["Cache-Control"] = "max-age=31536000"  // names change when a photo changes
        return response
    }

    // MARK: API

    private func api(_ request: HTTPRequest, _ p: [String]) -> HTTPResponse {
        let body = request.json()
        switch (request.method, p.first, p.count) {
        case ("GET", "version", 1):
            return .json(["version": version])
        case ("GET", "state", 1):
            return state()

        case ("POST", "racers", 1):
            store.addRacer(rank: body["rank"] as? String ?? "")
            return state(selected: store.selection)
        case ("PATCH", "racers", 2):
            return withRacer(p[1]) { patchRacer($0, body) }
        case ("DELETE", "racers", 2):
            return withRacer(p[1]) { store.deleteRacer($0.id); return state() }
        case ("POST", "racers", 3):
            return withRacer(p[1]) { racerAction($0, p[2]) }
        case ("PUT", "racers", 4) where p[2] == "photo", ("DELETE", "racers", 4) where p[2] == "photo":
            guard let kind = PhotoKind(rawValue: p[3]) else { return .error("Unknown photo", status: 404) }
            return withRacer(p[1]) { racer in
                if request.method == "DELETE" {
                    store.setPhoto(nil, kind: kind, racerID: racer.id)
                } else {
                    guard let image = NSImage(data: request.body) else { return .error("That isn't an image this app can read.", status: 400) }
                    store.setPhoto(image, kind: kind, racerID: racer.id)
                }
                return state()
            }

        case ("PATCH", "settings", 1):
            if let v = body["eventName"] as? String { store.data.eventName = v }
            if let v = body["maxWeightOz"] as? Double, v > 0 { store.data.maxWeightOz = v }
            if let v = body["imageFolderOnPC"] as? String { store.data.imageFolderOnPC = v }
            return state()

        case ("POST", "groups", 1):
            store.data.addGroup()
            return state()
        case ("PUT", "groups", 2) where p[1] == "order":
            let ids = (body["ids"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
            let byID = Dictionary(uniqueKeysWithValues: store.data.groups.map { ($0.id, $0) })
            let ordered = ids.compactMap { byID[$0] }
            if ordered.count == store.data.groups.count { store.data.groups = ordered }
            return state()
        case ("PATCH", "groups", 2):
            return withGroup(p[1]) { group in
                var note: String?
                if let v = body["rank"] as? String { note = store.data.renameRank(group.id, to: v) }
                if let v = body["subgroup"] as? String { store.data.renameSubgroup(group.id, to: v) }
                if let v = body["startNumber"] as? Int { store.data.setStartNumber(group.id, to: v) }
                return state(message: note)
            }
        case ("DELETE", "groups", 2):
            return withGroup(p[1]) { state(message: store.data.deleteGroup($0.id)) }
        case ("POST", "groups", 3) where p[2] == "renumber":
            return withGroup(p[1]) {
                state(message: store.data.renumber($0.id, onlyUnnumbered: body["onlyUnnumbered"] as? Bool ?? true))
            }

        case ("POST", "import", 1):
            let text = String(data: request.body, encoding: .utf8) ?? String(data: request.body, encoding: .windowsCP1252) ?? ""
            let summary = store.data.importRoster(text: text)
            return state(message: summary)
        case ("GET", "export", 1):
            return export(checkedInOnly: request.query["checkedInOnly"] == "1")

        default:
            return .error("Not found", status: 404)
        }
    }

    private func withRacer(_ id: String, _ action: (Racer) -> HTTPResponse) -> HTTPResponse {
        guard let uuid = UUID(uuidString: id), let racer = store.data.racers.first(where: { $0.id == uuid }) else {
            return .error("That racer was deleted on another computer.", status: 404)
        }
        return action(racer)
    }

    private func withGroup(_ id: String, _ action: (RaceGroup) -> HTTPResponse) -> HTTPResponse {
        guard let uuid = UUID(uuidString: id), let group = store.data.groups.first(where: { $0.id == uuid }) else {
            return .error("That group was deleted on another computer.", status: 404)
        }
        return action(group)
    }

    /// Applies only the fields a browser changed, so two people editing different
    /// fields of the same racer don't overwrite each other. The same rules as the Mac app apply.
    private func patchRacer(_ old: Racer, _ patch: [String: Any]) -> HTTPResponse {
        var patch = patch
        for locked in ["id", "racerPhoto", "carPhoto", "checkedInAt"] { patch.removeValue(forKey: locked) }
        guard let racer = try? merged(old, patch) else { return .error("Couldn't apply that change.", status: 400) }
        replace(store.data.applyingEditRules(racer, was: old))
        return state()
    }

    private func racerAction(_ racer: Racer, _ action: String) -> HTTPResponse {
        var racer = racer
        switch action {
        case "checkin":
            if let blocker = store.data.checkInBlocker(racer) { return .error(blocker, status: 409) }
            racer.checkedInAt = Date()
            replace(racer)
            return state()
        case "undo-checkin":
            racer.checkedInAt = nil
            replace(racer)
            return state()
        case "next-number":
            racer.carNumber = store.data.nextCarNumber(for: racer)
            replace(racer)
            return state()
        case "add-car":
            store.addCar(for: racer)
            return state(selected: store.selection)
        default:
            return .error("Not found", status: 404)
        }
    }

    private func replace(_ racer: Racer) {
        if let i = store.data.racers.firstIndex(where: { $0.id == racer.id }) { store.data.racers[i] = racer }
    }

    private func merged<T: Codable>(_ value: T, _ patch: [String: Any]) throws -> T {
        func merge(_ base: inout [String: Any], _ patch: [String: Any]) {
            for (key, new) in patch {
                if let sub = new as? [String: Any], var current = base[key] as? [String: Any] {
                    merge(&current, sub)
                    base[key] = current
                } else {
                    base[key] = new
                }
            }
        }
        var object = try JSONSerialization.jsonObject(with: Self.encoder.encode(value)) as? [String: Any] ?? [:]
        merge(&object, patch)
        return try Self.decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func export(checkedInOnly: Bool) -> HTTPResponse {
        let racers = (checkedInOnly ? store.data.racers.filter(\.isCheckedIn) : store.data.racers)
        guard !racers.isEmpty else {
            return .error(checkedInOnly ? "No racers are checked in yet." : "There are no racers to export.", status: 409)
        }
        let problems = store.data.exportProblems(racers)
        guard problems.isEmpty else {
            return .error("Fix these before exporting:\n\n" + problems.prefix(12).joined(separator: "\n")
                          + (problems.count > 12 ? "\n…and \(problems.count - 12) more." : ""), status: 409)
        }
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent("derby-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        do {
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            let sorted = racers.sorted(by: Racer.displayOrder)
            let dir = try store.writeExport(sorted, into: temp)
            let zip = temp.appendingPathComponent("export.zip")
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-c", "-k", "--norsrc", "--keepParent", dir.path, zip.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { return .error("Couldn't make the zip file.", status: 500) }
            var response = HTTPResponse.data(try Data(contentsOf: zip), type: "application/zip")
            let name = dir.lastPathComponent.replacingOccurrences(of: "\"", with: "")
            response.headers["Content-Disposition"] = "attachment; filename=\"\(name).zip\""
            return response
        } catch {
            return .error("Export failed: \(error.localizedDescription)", status: 500)
        }
    }

    // MARK: State

    private struct Problems: Encodable {
        var carNumber: String?
        var checkIn: String?
    }

    private struct State: Encodable {
        var version: Int
        var event: EventData
        var problems: [String: Problems]
        var counts: [String: Int]
        var folder: String
        var selected: String?
        var message: String?
    }

    private func state(selected: Racer.ID? = nil, message: String? = nil) -> HTTPResponse {
        var problems: [String: Problems] = [:]
        for r in store.data.racers {
            problems[r.id.uuidString] = Problems(carNumber: store.data.carNumberProblem(for: r), checkIn: store.data.checkInBlocker(r))
        }
        var counts: [String: Int] = [:]
        for g in store.data.groups { counts[g.rank] = store.data.carCount(rank: g.rank) }
        let value = State(version: version, event: store.data, problems: problems, counts: counts,
                          folder: store.folder.path, selected: selected?.uuidString, message: message)
        guard let data = try? Self.encoder.encode(value) else { return .error("Couldn't read the event.", status: 500) }
        return .data(data, type: "application/json; charset=utf-8")
    }
}
