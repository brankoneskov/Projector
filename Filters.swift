//
// Filters.swift
// Projector
//

import Foundation
import Combine

final class Filters: ObservableObject {
    @Published var query: String = ""
    @Published var room: String = "All Rooms"
    @Published var client: String = "All Clients"
    @Published var projectID: UUID? = nil
    @Published var personID: UUID? = nil
    @Published var day: Date = Date()

    func reset() {
        query = ""
        room = "All Rooms"
        client = "All Clients"
        projectID = nil
        personID = nil
    }
}
