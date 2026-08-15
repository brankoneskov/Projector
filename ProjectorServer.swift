//
//  ProjectorServer.swift
//  Projector
//
//  Embedded, technician-authorised HTTP API for Projector Go.
//  No route maps an untrusted request path directly to the filesystem.
//


import Foundation
import Network
import SwiftUI
import Combine

final class ProjectorServer: ObservableObject {
    static let shared = ProjectorServer()

    @Published var isRunning = false
    @Published var port: UInt16 = 8765
    @Published var lastError: String?
    @Published var requestLog: [ServerLogEntry] = []

    private let queue = DispatchQueue(label: "projector.server", qos: .userInitiated)
    private let maxHeaderBytes = 16 * 1024
    private let maxBodyBytes = 64 * 1024
    private let maxThreadBytes = 1024 * 1024
    private let maxLogEntries = 50
    private var listener: NWListener?
    private var recentPairingFailures: [Date] = []

    private init() {}

    // MARK: - Start / Stop

    func start() {
        stop()
        lastError = nil

        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                lastError = "Invalid server port."
                return
            }
            listener = try NWListener(using: params, on: endpointPort)
        } catch {
            lastError = "Could not create listener: \(error.localizedDescription)"
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }
        listener?.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.lastError = nil
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                case .cancelled:
                    self?.isRunning = false
                default:
                    break
                }
            }
        }
        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Connection handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            if error != nil {
                connection.cancel()
                return
            }

            var buffer = accumulated
            if let data { buffer.append(data) }
            if buffer.count > self.maxHeaderBytes + self.maxBodyBytes {
                self.sendAndClose(self.errorResponse(413, "request_too_large"), on: connection)
                return
            }

            switch self.parseRequest(buffer) {
            case .incomplete:
                if isComplete {
                    self.sendAndClose(self.errorResponse(400, "incomplete_request"), on: connection)
                } else {
                    self.receiveRequest(on: connection, accumulated: buffer)
                }
            case .failure(let response):
                self.sendAndClose(response, on: connection)
            case .success(let request):
                let response = self.route(request)
                self.sendAndClose(response, on: connection)
                self.log(method: request.method, path: request.path, status: response.status)
            }
        }
    }

    // MARK: - Router

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        if request.method == "OPTIONS" {
            return HTTPResponse(status: 204, body: Data(), contentType: "text/plain")
        }

        if request.method == "GET" && request.path == "/ping" {
            return jsonResponse(200, ["status": "ok", "app": "Projector", "api": "v1"])
        }

        if request.method == "POST" && request.path == "/v1/pair" {
            return exchangePairingCode(request.body)
        }

        guard let technician = authenticate(request.headers) else {
            return errorResponse(401, "unauthorized")
        }

        if request.method == "GET" && request.path == "/v1/me" {
            return jsonResponse(200, [
                "personID": technician.personID.uuidString,
                "personName": technician.personName
            ])
        }

        if request.method == "GET" && request.path == "/v1/sessions" {
            return sessionsResponse(for: technician, query: request.query)
        }

        if request.method == "POST" && request.path == "/v1/devices" {
            return registerDevice(request.body, for: technician)
        }

        if let sessionID = sessionID(from: request.path) {
            guard technicianCanAccess(sessionID: sessionID, personID: technician.personID) else {
                return errorResponse(403, "forbidden")
            }
            switch request.method {
            case "GET":
                return readMessages(sessionID: sessionID)
            case "POST":
                return appendMessage(request.body, sessionID: sessionID, technician: technician)
            default:
                return errorResponse(405, "method_not_allowed")
            }
        }

        // The unauthorised file API was deliberately retired.
        if request.path == "/index.json" || request.path == "/people_index.json" ||
            request.path.hasPrefix("/Messages/") || request.path.hasPrefix("/tokens/") {
            return errorResponse(410, "legacy_endpoint_retired")
        }

        return errorResponse(404, "not_found")
    }

    // MARK: - Pairing and identity

    private struct PairRequest: Decodable { let code: String }

    private func exchangePairingCode(_ body: Data) -> HTTPResponse {
        let cutoff = Date().addingTimeInterval(-60)
        recentPairingFailures.removeAll { $0 < cutoff }
        guard recentPairingFailures.count < 20 else {
            return errorResponse(429, "too_many_pairing_attempts")
        }
        guard let request = try? JSONDecoder().decode(PairRequest.self, from: body),
              !request.code.isEmpty else {
            recentPairingFailures.append(Date())
            return errorResponse(400, "invalid_pairing_request")
        }
        guard let exchange = ServerAuth.shared.exchange(pairingCode: request.code) else {
            recentPairingFailures.append(Date())
            return errorResponse(401, "invalid_or_expired_pairing_code")
        }
        recentPairingFailures.removeAll()
        return jsonResponse(200, [
            "accessToken": exchange.accessToken,
            "personID": exchange.technician.personID.uuidString,
            "personName": exchange.technician.personName
        ])
    }

    private func authenticate(_ headers: [String: String]) -> AuthenticatedTechnician? {
        guard let authorization = headers["authorization"],
              authorization.count > 7,
              authorization.prefix(7).lowercased() == "bearer " else { return nil }
        let token = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        guard let authenticated = ServerAuth.shared.authenticate(bearerToken: token),
              let person = peopleIndex().first(where: {
                  $0.id.caseInsensitiveCompare(authenticated.personID.uuidString) == .orderedSame
              }), person.isActive else { return nil }
        return AuthenticatedTechnician(personID: authenticated.personID, personName: person.name)
    }

    // MARK: - Sessions

    private struct PersonIndexEntry: Decodable {
        let id: String
        let name: String
        let isActive: Bool
    }

    private struct SessionIndexEntry: Codable {
        let id: String
        let title: String
        let room: String
        let client: String
        let start: Date
        let durationMinutes: Int
        let peopleIDs: [String]
        let notes: String
        let projectID: String?
        let projectName: String?
    }

    private struct MobileSessionEntry: Encodable {
        let id: String
        let title: String
        let room: String
        let client: String
        let start: Date
        let durationMinutes: Int
        let notes: String
        let projectName: String?
    }

    private func peopleIndex() -> [PersonIndexEntry] {
        guard let data = try? Data(contentsOf: DataPaths.file("people_index.json")) else { return [] }
        return (try? JSONDecoder().decode([PersonIndexEntry].self, from: data)) ?? []
    }

    private func sessionIndex() -> [SessionIndexEntry]? {
        guard let data = try? Data(contentsOf: DataPaths.file("index.json")) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([SessionIndexEntry].self, from: data)
    }

    private func sessionsResponse(
        for technician: AuthenticatedTechnician,
        query: [String: String]
    ) -> HTTPResponse {
        guard let sessions = sessionIndex() else {
            return errorResponse(503, "session_index_unavailable")
        }
        let requestedDays = Int(query["days"] ?? "7") ?? 7
        let days = [7, 14, 30].contains(requestedDays) ? requestedDays : 7
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: days, to: start) ?? Date.distantFuture
        let personID = technician.personID.uuidString

        let filtered = sessions.filter { session in
            session.peopleIDs.contains { $0.caseInsensitiveCompare(personID) == .orderedSame } &&
            session.start >= start && session.start < end
        }.sorted { $0.start < $1.start }.map { session in
            MobileSessionEntry(
                id: session.id,
                title: session.title,
                room: session.room,
                client: session.client,
                start: session.start,
                durationMinutes: session.durationMinutes,
                notes: session.notes,
                projectName: session.projectName
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(filtered) else {
            return errorResponse(500, "encoding_failed")
        }
        return HTTPResponse(status: 200, body: data, contentType: "application/json")
    }

    private func technicianCanAccess(sessionID: UUID, personID: UUID) -> Bool {
        guard let session = sessionIndex()?.first(where: {
            $0.id.caseInsensitiveCompare(sessionID.uuidString) == .orderedSame
        }) else { return false }
        return session.peopleIDs.contains {
            $0.caseInsensitiveCompare(personID.uuidString) == .orderedSame
        }
    }

    private func sessionID(from path: String) -> UUID? {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count == 4,
              components[0] == "v1",
              components[1] == "sessions",
              components[3] == "messages" else { return nil }
        return UUID(uuidString: String(components[2]))
    }

    // MARK: - Messages

    private struct IncomingMessage: Decodable { let text: String }

    private func messageURL(_ sessionID: UUID) -> URL {
        DataPaths.folder("Messages").appendingPathComponent("\(sessionID.uuidString).json")
    }

    private func readMessages(sessionID: UUID) -> HTTPResponse {
        MessageStore.persistenceLock.lock()
        defer { MessageStore.persistenceLock.unlock() }
        let url = messageURL(sessionID)
        if !FileManager.default.fileExists(atPath: url.path) {
            return encodedThread(MessageThread(sessionID: sessionID), status: 200)
        }
        guard let data = try? Data(contentsOf: url), data.count <= maxThreadBytes else {
            return errorResponse(500, "message_thread_unavailable")
        }
        return HTTPResponse(status: 200, body: data, contentType: "application/json")
    }

    private func appendMessage(
        _ body: Data,
        sessionID: UUID,
        technician: AuthenticatedTechnician
    ) -> HTTPResponse {
        guard let incoming = try? JSONDecoder().decode(IncomingMessage.self, from: body) else {
            return errorResponse(400, "invalid_message")
        }
        let text = incoming.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4_000 else {
            return errorResponse(422, "message_must_be_1_to_4000_characters")
        }

        MessageStore.persistenceLock.lock()
        defer { MessageStore.persistenceLock.unlock() }
        let url = messageURL(sessionID)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var thread: MessageThread
        if FileManager.default.fileExists(atPath: url.path) {
            guard let existingData = try? Data(contentsOf: url),
                  existingData.count <= maxThreadBytes,
                  let existingThread = try? decoder.decode(MessageThread.self, from: existingData) else {
                return errorResponse(500, "message_thread_unavailable")
            }
            thread = existingThread
        } else {
            thread = MessageThread(sessionID: sessionID)
        }
        guard thread.sessionID == sessionID else {
            return errorResponse(409, "message_thread_mismatch")
        }

        thread.messages.append(ChatMessage(
            senderName: technician.personName,
            senderType: .tech,
            text: text,
            timestamp: Date()
        ))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(thread), data.count <= maxThreadBytes else {
            return errorResponse(500, "message_save_failed")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return errorResponse(500, "message_save_failed")
        }
        DispatchQueue.main.async { MessageStore.shared.reload() }
        return HTTPResponse(status: 201, body: data, contentType: "application/json")
    }

    private func encodedThread(_ thread: MessageThread, status: Int) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(thread) else {
            return errorResponse(500, "encoding_failed")
        }
        return HTTPResponse(status: status, body: data, contentType: "application/json")
    }

    // MARK: - Device registration

    private struct DeviceRequest: Decodable {
        let deviceID: String
        let platform: String
        let token: String
    }

    private func registerDevice(_ body: Data, for technician: AuthenticatedTechnician) -> HTTPResponse {
        guard let incoming = try? JSONDecoder().decode(DeviceRequest.self, from: body),
              let deviceID = UUID(uuidString: incoming.deviceID),
              incoming.platform == "ios" || incoming.platform == "android",
              incoming.token.count >= 20,
              incoming.token.count <= 4_096 else {
            return errorResponse(400, "invalid_device_registration")
        }

        let registration = DeviceRegistration(
            deviceID: deviceID,
            personID: technician.personID,
            personName: technician.personName,
            platform: incoming.platform,
            token: incoming.token,
            updatedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(registration) else {
            return errorResponse(500, "encoding_failed")
        }

        let folder = DataPaths.privateFolder("DeviceTokens")
            .appendingPathComponent(technician.personID.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(
                to: folder.appendingPathComponent("\(deviceID.uuidString).json"),
                options: .atomic
            )
            return jsonResponse(200, ["status": "registered"])
        } catch {
            return errorResponse(500, "device_registration_failed")
        }
    }

    // MARK: - HTTP parsing

    private enum RequestParseResult {
        case incomplete
        case failure(HTTPResponse)
        case success(HTTPRequest)
    }

    private func parseRequest(_ data: Data) -> RequestParseResult {
        let delimiter = Data([13, 10, 13, 10])
        guard let headerRange = data.range(of: delimiter) else {
            return data.count > maxHeaderBytes
                ? .failure(errorResponse(413, "headers_too_large"))
                : .incomplete
        }
        guard headerRange.lowerBound <= maxHeaderBytes,
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return .failure(errorResponse(400, "invalid_headers"))
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else {
            return .failure(errorResponse(400, "invalid_request_line"))
        }
        let requestParts = first.split(separator: " ", omittingEmptySubsequences: true)
        guard requestParts.count == 3 else {
            return .failure(errorResponse(400, "invalid_request_line"))
        }
        let method = String(requestParts[0]).uppercased()
        let target = String(requestParts[1])
        guard ["GET", "POST", "OPTIONS"].contains(method),
              target.hasPrefix("/"),
              !target.contains("#"),
              target.count <= 2_048 else {
            return .failure(errorResponse(405, "method_not_allowed"))
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                return .failure(errorResponse(400, "invalid_header"))
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                return .failure(errorResponse(400, "invalid_header"))
            }
            if let existing = headers[key] {
                guard key != "content-length", key != "transfer-encoding" else {
                    return .failure(errorResponse(400, "duplicate_framing_header"))
                }
                headers[key] = "\(existing), \(value)"
            } else {
                headers[key] = value
            }
        }
        if headers["transfer-encoding"] != nil {
            return .failure(errorResponse(400, "transfer_encoding_not_supported"))
        }

        let bodyStart = headerRange.upperBound
        let contentLength: Int
        if let rawLength = headers["content-length"] {
            guard let parsed = Int(rawLength), parsed >= 0, parsed <= maxBodyBytes else {
                return .failure(errorResponse(413, "request_body_too_large"))
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard data.count >= bodyStart + contentLength else { return .incomplete }
        if method == "POST" && headers["content-length"] == nil {
            return .failure(errorResponse(411, "content_length_required"))
        }

        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        guard let components = URLComponents(string: "http://projector.local\(target)") else {
            return .failure(errorResponse(400, "invalid_request_target"))
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        return .success(HTTPRequest(
            method: method,
            path: components.path,
            query: query,
            headers: headers,
            body: body
        ))
    }

    // MARK: - Responses

    private func jsonResponse<T: Encodable>(_ status: Int, _ value: T) -> HTTPResponse {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else {
            return errorResponse(500, "encoding_failed")
        }
        return HTTPResponse(status: status, body: data, contentType: "application/json")
    }

    private func errorResponse(_ status: Int, _ code: String) -> HTTPResponse {
        let escaped = code.replacingOccurrences(of: "\"", with: "")
        return HTTPResponse(
            status: status,
            body: Data("{\"error\":\"\(escaped)\"}".utf8),
            contentType: "application/json"
        )
    }

    private func sendAndClose(_ response: HTTPResponse, on connection: NWConnection) {
        let header = [
            "HTTP/1.1 \(response.status) \(statusText(response.status))",
            "Content-Type: \(response.contentType); charset=utf-8",
            "Content-Length: \(response.body.count)",
            "Cache-Control: no-store",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, Authorization",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")

        var data = Data(header.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 422: return "Unprocessable Content"
        case 429: return "Too Many Requests"
        case 503: return "Service Unavailable"
        default: return "Internal Server Error"
        }
    }

    // MARK: - Logging / local address

    private func log(method: String, path: String, status: Int) {
        let entry = ServerLogEntry(method: method, path: path, status: status, time: Date())
        DispatchQueue.main.async {
            self.requestLog.insert(entry, at: 0)
            if self.requestLog.count > self.maxLogEntries {
                self.requestLog = Array(self.requestLog.prefix(self.maxLogEntries))
            }
        }
    }

    var localIPAddress: String {
        var address = "unknown"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }

        var ptr = firstAddr
        while true {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET), String(cString: interface.ifa_name) == "en0" {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    interface.ifa_addr,
                    socklen_t(interface.ifa_addr.pointee.sa_len),
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                address = String(cString: hostname)
            }
            guard let next = interface.ifa_next else { break }
            ptr = next
        }
        return address
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data
}

struct HTTPResponse {
    let status: Int
    let body: Data
    let contentType: String
}

struct ServerLogEntry: Identifiable {
    let id = UUID()
    let method: String
    let path: String
    let status: Int
    let time: Date
}

