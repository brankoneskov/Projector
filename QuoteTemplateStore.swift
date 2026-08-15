//
//  QuoteTemplateStore.swift
//  Projector
//
//  Created by Branko Neskov on 15/11/2025.
//
import Foundation
import Combine

@MainActor
final class QuoteTemplateStore: ObservableObject {
    static let shared = QuoteTemplateStore()

    @Published var templates: [QuoteTemplate] = [] {
        didSet { save() }
    }

    private init() { load() }

    // MARK: - Persistence

    private var url: URL {
        DataPaths.file("quoteTemplates.json")
    }

    private func load() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([QuoteTemplate].self, from: data) {
            templates = decoded
        } else {
            templates = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(templates) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - CRUD

    func add(_ t: QuoteTemplate) {
        templates.append(t)
    }

    func delete(_ t: QuoteTemplate) {
        templates.removeAll { $0.id == t.id }
    }
}

