import Foundation
import Network

struct HTTPRequest: Sendable {
    var method: String
    /// Percent-decoded path without the query, e.g. /api/racers/123.
    var path: String
    var query: [String: String]
    /// Header names are lowercased.
    var headers: [String: String]
    var body: Data

    var parts: [String] { path.split(separator: "/").map(String.init) }

    func json() -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    }
}

struct HTTPResponse: Sendable {
    var status: Int
    var headers: [String: String] = [:]
    var body = Data()

    static func data(_ body: Data, type: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": type], body: body)
    }

    static func text(_ text: String, status: Int = 200) -> HTTPResponse {
        data(Data(text.utf8), type: "text/plain; charset=utf-8", status: status)
    }

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        data((try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8),
             type: "application/json; charset=utf-8", status: status)
    }

    static func error(_ message: String, status: Int) -> HTTPResponse {
        json(["error": message], status: status)
    }
}

/// A small HTTP/1.1 server on Network.framework: one request per connection, which is
/// plenty for a handful of check-in computers on a local network.
/// Started and stopped on the main actor; connections are handled on `queue`.
@MainActor
final class HTTPServer {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "derby.http")
    private let handler: Handler
    /// Called on the main actor: nil when listening, otherwise an error to show.
    var onStateChange: ((String?) -> Void)?

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func start(port: UInt16, serviceName: String) throws {
        stop()
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw URLError(.badURL) }
        let listener = try NWListener(using: params, on: nwPort)
        // Advertised with Bonjour so Macs can find it in Safari's Bonjour list.
        listener.service = NWListener.Service(name: serviceName, type: "_http._tcp")
        // Network.framework calls these on `queue`, so they must not inherit the main actor.
        listener.stateUpdateHandler = { @Sendable [weak self] state in
            let message: String?? = switch state {
            case .ready: .some(nil)
            case .failed(let error): .some(Self.describe(error, port: port))
            default: .none
            }
            if let message { Task { @MainActor in self?.onStateChange?(message) } }
        }
        listener.newConnectionHandler = { @Sendable [handler, queue] connection in
            HTTPConnection(connection: connection, handler: handler).start(on: queue)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    nonisolated private static func describe(_ error: NWError, port: UInt16) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "Port \(port) is already in use by another program. Choose a different port."
        }
        return error.localizedDescription
    }
}

/// One request and its response. Only touched from the server queue's callbacks, one at a
/// time, plus `send` from the task that ran the handler; NWConnection itself is thread-safe.
private final class HTTPConnection: @unchecked Sendable {
    private static let maxBody = 30 * 1024 * 1024
    private let connection: NWConnection
    private let handler: HTTPServer.Handler
    private var buffer = Data()

    init(connection: NWConnection, handler: @escaping HTTPServer.Handler) {
        self.connection = connection
        self.handler = handler
    }

    func start(on queue: DispatchQueue) {
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { data, _, isComplete, error in
            if let data { self.buffer.append(data) }
            switch self.parse() {
            case .request(let request):
                Task {
                    let response = await self.handler(request)
                    self.send(response)
                }
            case .tooLarge:
                self.send(.error("That upload is too large.", status: 413))
            case .incomplete:
                if isComplete || error != nil { self.connection.cancel() } else { self.receive() }
            case .bad:
                self.send(.error("Bad request", status: 400))
            }
        }
    }

    private enum ParseResult { case request(HTTPRequest), incomplete, tooLarge, bad }

    private func parse() -> ParseResult {
        guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > 64 * 1024 ? .bad : .incomplete
        }
        guard let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) else { return .bad }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count >= 2 else { return .bad }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        if length > Self.maxBody { return .tooLarge }
        let bodyStart = end.upperBound
        guard buffer.count - bodyStart >= length else { return .incomplete }

        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let path = components?.percentEncodedPath.removingPercentEncoding ?? target
        return .request(HTTPRequest(
            method: String(requestLine[0]).uppercased(), path: path, query: query, headers: headers,
            body: Data(buffer[bodyStart..<(bodyStart + length)])))
    }

    private func send(_ response: HTTPResponse) {
        var head = "HTTP/1.1 \(response.status) \(Self.reason(response.status))\r\n"
        var headers = response.headers
        headers["Content-Length"] = String(response.body.count)
        headers["Connection"] = "close"
        if headers["Cache-Control"] == nil { headers["Cache-Control"] = "no-store" }
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        connection.send(content: Data(head.utf8) + response.body, completion: .contentProcessed { _ in
            self.connection.cancel()
        })
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        default: status < 400 ? "OK" : "Error"
        }
    }
}
