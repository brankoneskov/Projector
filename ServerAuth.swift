//
//  ServerAuth.swift
//  Projector
//
//  Technician-specific authentication for Projector Go.
//  Pairing codes are short-lived and one-time. Persistent access tokens are
//  stored only as SHA-256 hashes, so the original token cannot be recovered
//  from Projector's local authentication store.
//


import Foundation
import Combine
import CryptoKit

struct AuthenticatedTechnician: Equatable {
    let personID: UUID
    let personName: String
}

struct TechnicianPairing: Equatable {
    let code: String
    let personID: UUID
    let personName: String
    let expiresAt: Date

    var isExpired: Bool { expiresAt <= Date() }
}

struct PairingExchangeResult {
    let accessToken: String
    let technician: AuthenticatedTechnician
}

final class ServerAuth: ObservableObject {
    static let shared = ServerAuth()

    @Published private(set) var pairedPersonIDs: Set<UUID> = []
    @Published private(set) var activePairing: TechnicianPairing?

    private struct StoredCredential: Codable {
        let personID: UUID
        var personName: String
        let tokenHash: String
        let createdAt: Date
    }

    private struct StoredFile: Codable {
        var version: Int = 2
        var credentials: [StoredCredential]
    }

    private let lock = NSLock()
    private var credentials: [StoredCredential] = []
    private var pendingPairing: TechnicianPairing?

    private var fileURL: URL {
        DataPaths.privateFolder("ServerAuth").appendingPathComponent("server_auth_v2.json")
    }

    private init() {
        credentials = load()
        pairedPersonIDs = Set(credentials.map(\.personID))
    }

    // MARK: - Pairing

    /// Creates one short-lived pairing code. Creating another code replaces
    /// the previous unredeemed code, but does not revoke an existing device.
    @discardableResult
    func createPairing(for person: Person, validity: TimeInterval = 15 * 60) -> TechnicianPairing {
        let code = makePairingCode()
        let pairing = TechnicianPairing(
            code: code,
            personID: person.id,
            personName: person.name,
            expiresAt: Date().addingTimeInterval(validity)
        )

        lock.lock()
        pendingPairing = pairing
        lock.unlock()
        publishActivePairing(pairing)
        return pairing
    }

    func cancelPairing() {
        lock.lock()
        pendingPairing = nil
        lock.unlock()
        publishActivePairing(nil)
    }

    /// Exchanges a one-time code for a personal bearer token. Re-pairing the
    /// same person revokes their previous token and registered devices.
    func exchange(pairingCode rawCode: String) -> PairingExchangeResult? {
        let code = normalizePairingCode(rawCode)
        let result: PairingExchangeResult?
        var changedPersonID: UUID?
        let shouldClearPublishedPairing: Bool

        lock.lock()
        if let pendingPairing,
           !pendingPairing.isExpired,
           constantTimeEqual(normalizePairingCode(pendingPairing.code), code) {
            let token = makeAccessToken()
            let credential = StoredCredential(
                personID: pendingPairing.personID,
                personName: pendingPairing.personName,
                tokenHash: hash(token),
                createdAt: Date()
            )
            credentials.removeAll { $0.personID == pendingPairing.personID }
            credentials.append(credential)
            self.pendingPairing = nil
            persistLocked()
            changedPersonID = credential.personID
            result = PairingExchangeResult(
                accessToken: token,
                technician: AuthenticatedTechnician(
                    personID: credential.personID,
                    personName: credential.personName
                )
            )
            shouldClearPublishedPairing = true
        } else {
            if pendingPairing?.isExpired == true {
                pendingPairing = nil
            }
            result = nil
            shouldClearPublishedPairing = pendingPairing == nil
        }
        lock.unlock()

        if let changedPersonID {
            removeRegisteredDevices(for: changedPersonID)
            publishState(activePairing: nil)
        } else if shouldClearPublishedPairing {
            publishActivePairing(nil)
        }
        return result
    }

    // MARK: - Authentication

    func authenticate(bearerToken rawToken: String) -> AuthenticatedTechnician? {
        let suppliedHash = hash(rawToken)
        lock.lock()
        defer { lock.unlock() }

        guard let credential = credentials.first(where: {
            constantTimeEqual($0.tokenHash, suppliedHash)
        }) else { return nil }

        return AuthenticatedTechnician(
            personID: credential.personID,
            personName: credential.personName
        )
    }

    func isPaired(_ personID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return credentials.contains { $0.personID == personID }
    }

    func revoke(_ personID: UUID) {
        lock.lock()
        credentials.removeAll { $0.personID == personID }
        if pendingPairing?.personID == personID {
            pendingPairing = nil
        }
        persistLocked()
        lock.unlock()

        removeRegisteredDevices(for: personID)
        publishState(activePairing: nil)
    }

    // MARK: - Persistence

    private func load() -> [StoredCredential] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(StoredFile.self, from: data),
              stored.version == 2 else { return [] }
        return stored.credentials
    }

    /// Must be called while `lock` is held.
    private func persistLocked() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(StoredFile(credentials: credentials)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func removeRegisteredDevices(for personID: UUID) {
        let folder = DataPaths.privateFolder("DeviceTokens").appendingPathComponent(
            personID.uuidString,
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: folder)
    }

    // MARK: - Token helpers

    private func makePairingCode() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let value = String(raw.prefix(12)).uppercased()
        return "\(value.prefix(4))-\(value.dropFirst(4).prefix(4))-\(value.dropFirst(8).prefix(4))"
    }

    private func makeAccessToken() -> String {
        let first = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let second = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return "pg_\(first)\(second)".lowercased()
    }

    private func normalizePairingCode(_ value: String) -> String {
        value.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
    }

    // MARK: - Published state

    private func publishActivePairing(_ pairing: TechnicianPairing?) {
        DispatchQueue.main.async {
            self.activePairing = pairing
        }
    }

    private func publishState(activePairing: TechnicianPairing?) {
        lock.lock()
        let ids = Set(credentials.map(\.personID))
        lock.unlock()
        DispatchQueue.main.async {
            self.pairedPersonIDs = ids
            self.activePairing = activePairing
        }
    }
}

