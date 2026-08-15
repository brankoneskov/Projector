//
//  MessagingModels.swift
//  Projector
//

import Foundation

// MARK: - Sender Type

enum SenderType: String, Codable {
    case tech   = "tech"
    case studio = "studio"
}

// MARK: - Chat Message

struct ChatMessage: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString  // iOS sends numeric string IDs, Mac sends UUID strings
    var senderName: String
    var senderType: SenderType
    var text: String
    var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id, senderName, senderType, text, timestamp
    }
    init(id: String = UUID().uuidString, senderName: String, senderType: SenderType, text: String, timestamp: Date = Date()) {
        self.id = id
        self.senderName = senderName
        self.senderType = senderType
        self.text = text
        self.timestamp = timestamp
    }
    // Custom date decoding to handle both standard ISO8601 and microsecond variants
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        senderName = try c.decode(String.self, forKey: .senderName)
        senderType = try c.decode(SenderType.self, forKey: .senderType)
        text       = try c.decode(String.self, forKey: .text)

        let tsString = try c.decode(String.self, forKey: .timestamp)
        // Try standard ISO8601 first, then with fractional seconds
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: tsString) {
            timestamp = date
        } else {
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = iso.date(from: tsString) ?? Date()
        }
    }
}

// MARK: - Message Thread

struct MessageThread: Identifiable, Codable {
    var id: UUID { sessionID }
    var sessionID: UUID
    var messages: [ChatMessage] = []

    /// Most recent message timestamp, for sorting
    var lastActivity: Date {
        messages.last?.timestamp ?? .distantPast
    }

    /// True if the last message was sent by a tech (needs studio attention)
    var hasUnreadFromTech: Bool {
        messages.last?.senderType == .tech
    }
}
