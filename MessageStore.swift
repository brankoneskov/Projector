//
//  MessageStore.swift
//  Projector
//

import Foundation
import Combine

final class MessageStore: ObservableObject {
    static let shared = MessageStore()
    static let persistenceLock = NSRecursiveLock()

    @Published var threads: [MessageThread] = []

    private var folderURL: URL { DataPaths.folder("Messages") }
    private var reloadTimer: Timer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
        cleanupOldThreads()
        startTimer()
    }

    // MARK: - Load

    func load() {
        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil)
                .filter({ $0.pathExtension.lowercased() == "json" }) else { return }

        var loaded: [MessageThread] = []
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let thread = try? decoder.decode(MessageThread.self, from: data) else { continue }
            loaded.append(thread)
        }

        DispatchQueue.main.async {
            self.threads = loaded.sorted { $0.lastActivity > $1.lastActivity }
        }
    }

    func reload() { load() }

    // MARK: - Cleanup

    /// Delete resolved threads older than `days` days.
    /// A thread is considered resolved if the last message is from studio.
    /// Unresolved threads (last message from tech) are kept regardless of age.
    func cleanupOldThreads(olderThan days: Int = 60) {
        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var removed = 0
        for thread in threads {
            guard thread.lastActivity < cutoff else { continue }
            guard !thread.hasUnreadFromTech else { continue }  // keep unresolved
            let url = folderURL.appendingPathComponent("\(thread.sessionID.uuidString).json")
            try? fm.removeItem(at: url)
            removed += 1
        }
        if removed > 0 {
            print("🧹 Cleaned up \(removed) old message threads")
            load()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        reloadTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.load()
        }
    }

    // MARK: - Write

    /// Send a message from the studio to a session thread
    func sendMessage(sessionID: UUID, text: String, senderName: String) {
        let message = ChatMessage(
            senderName: senderName,
            senderType: .studio,
            text: text,
            timestamp: Date()
        )
        appendMessage(message, to: sessionID)
        // Notify only devices authenticated as people assigned to the session.
        let assignedPersonIDs: [UUID]
        if let session = SessionStore.shared.sessions.first(where: { $0.id == sessionID }) {
            assignedPersonIDs = session.peopleIDs
        } else {
            assignedPersonIDs = []
        }
        APNsSender.shared.sendNewMessage(
            from: senderName,
            text: text,
            forPeopleIDs: assignedPersonIDs
        )
    }

    private func appendMessage(_ message: ChatMessage, to sessionID: UUID) {
        // Always reload this thread while holding the shared lock. The embedded
        // server may have appended a technician message since the last UI reload.
        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }
        let url = folderURL.appendingPathComponent("\(sessionID.uuidString).json")
        var thread: MessageThread
        if let data = try? Data(contentsOf: url),
           let latest = try? decoder.decode(MessageThread.self, from: data) {
            thread = latest
        } else {
            thread = threads.first(where: { $0.sessionID == sessionID })
                ?? MessageThread(sessionID: sessionID)
        }

        thread.messages.append(message)

        // Save to disk
        save(thread)

        // Update in-memory
        if let idx = threads.firstIndex(where: { $0.sessionID == sessionID }) {
            threads[idx] = thread
        } else {
            threads.insert(thread, at: 0)
        }
        threads.sort { $0.lastActivity > $1.lastActivity }
    }

    private func save(_ thread: MessageThread) {
        Self.persistenceLock.lock()
        defer { Self.persistenceLock.unlock() }
        guard let data = try? encoder.encode(thread) else { return }
        let url = folderURL.appendingPathComponent("\(thread.sessionID.uuidString).json")
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Helpers

    func thread(for sessionID: UUID) -> MessageThread? {
        threads.first(where: { $0.sessionID == sessionID })
    }

    var unreadCount: Int {
        threads.filter { $0.hasUnreadFromTech }.count
    }
}

