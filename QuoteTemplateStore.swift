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

    private var isLoading = false

    @Published var templates: [QuoteTemplate] = [] {
        didSet { if !isLoading { save() } }
    }

    private init() { load() }

    // MARK: - Persistence

    private var url: URL {
        DataPaths.file("quoteTemplates.json")
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }

        guard FileManager.default.fileExists(atPath: url.path) else {
            templates = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            templates = try JSONDecoder().decode([QuoteTemplate].self, from: data)
        } catch {
            // Keep the on-disk file untouched so a transient or schema error
            // can never replace all templates with an empty array.
            print("⚠️ Failed to load quote templates: \(error.localizedDescription)")
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

