//
//  ClientModels.swift
//  Projector
//
//  Created by Branko Neskov on 27/10/2025.
//
import Foundation
import Combine

struct Client: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var contactName: String = ""
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var notes: String = ""
    var isActive: Bool = true
}

final class ClientsStore: ObservableObject {
    @Published var clients: [Client] = [] { didSet { save() } }
    static let shared = ClientsStore()
    private init() { load() }

    private let fileURL: URL = DataPaths.file("clients.json")

    private func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([Client].self, from: data)
            clients = decoded.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            clients = []  // seed empty
        }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(clients)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("ClientsStore save error:", error)
        }
    }

    // CRUD
    func add(_ c: Client) { clients.append(c); sort() }
    func update(_ c: Client) { if let i = clients.firstIndex(where: { $0.id == c.id }) { clients[i] = c; sort() } }
    func delete(_ c: Client) { clients.removeAll { $0.id == c.id } }
    private func sort() { clients.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending } }
}

