//
// TranslationStore.swift
// Projector
//
// Replaces the hardcoded dictionaries in ExportLocalization.swift.
// Translations are stored in a JSON file on disk and editable in-app.
//

import Foundation
import Combine

// MARK: - Model

struct TranslationEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var key: String                          // English source (canonical)
    var translations: [String: String]       // language code -> translated string

    func translation(for languageCode: String) -> String? {
        translations[languageCode]
    }

    /// Resolve this user-configured entry for an export language.
    /// English is stored in `key`; all other languages live in `translations`.
    func resolvedText(for languageCode: String) -> String? {
        if languageCode == "en" {
            let english = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return english.isEmpty ? nil : english
        }

        guard let value = translations[languageCode]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

// MARK: - Store

final class TranslationStore: ObservableObject {
    @Published var entries: [TranslationEntry] = []
    static let shared = TranslationStore()

    private var fileURL: URL { DataPaths.file("translations.json") }
    private var isLoading = false

    private init() { load() }

    // MARK: - Persistence

    func load() {
        isLoading = true
        defer { isLoading = false }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                entries = try JSONDecoder().decode([TranslationEntry].self, from: data)
                sort()
                print("✅ Loaded \(entries.count) translation entries")
                return
            } catch {
                print("⚠️ Failed to load translations: \(error.localizedDescription)")
                // Preserve the existing file. Never replace a user's dictionary
                // with seed data merely because one read or decode failed.
                entries = []
                return
            }
        }

        // First launch — seed from the hardcoded dictionaries
        seedFromLegacy()
        save()
    }

    func reload() { load() }

    func save() {
        guard !isLoading else { return }
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Save error (translations): \(error)")
        }
    }

    // MARK: - Lookup

    /// Normalise a string for matching: trim, collapse spaces, normalise dashes.
    private func normalise(_ s: String) -> String {
        let punctuationNormalised = s.trimmingCharacters(in: .whitespacesAndNewlines)
         .replacingOccurrences(of: "\u{2013}", with: "-")  // en-dash → hyphen
         .replacingOccurrences(of: "\u{2014}", with: "-")  // em-dash → hyphen
         .replacingOccurrences(of: "\u{2012}", with: "-")  // figure dash → hyphen

        // Collapse every run of spaces, tabs and newlines to a single space.
        return punctuationNormalised
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    func entry(withID id: UUID?) -> TranslationEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    /// Finds a unique dictionary entry whose English key or translated value
    /// matches the supplied text. This is only a compatibility/suggestion path;
    /// persisted UUID links remain authoritative.
    func entry(matching text: String) -> TranslationEntry? {
        let candidate = normalise(text)
        guard !candidate.isEmpty else { return nil }

        let matches = entries.filter { entry in
            if normalise(entry.key).caseInsensitiveCompare(candidate) == .orderedSame {
                return true
            }
            return entry.translations.values.contains {
                normalise($0).caseInsensitiveCompare(candidate) == .orderedSame
            }
        }

        // Never guess when two user-defined entries contain the same wording.
        return matches.count == 1 ? matches[0] : nil
    }

    func suggestedEntryID(for text: String) -> UUID? {
        entry(matching: text)?.id
    }

    func hasConfiguredText(
        entryID: UUID?,
        original: String,
        for languageCode: String
    ) -> Bool {
        let matchedEntry = entry(withID: entryID) ?? entry(matching: original)
        return matchedEntry?.resolvedText(for: languageCode) != nil
    }

    /// UUID-first resolution used by categories, services, units and budget
    /// lines. Missing entries or missing language values fall back unchanged.
    func resolve(
        entryID: UUID?,
        original: String,
        to languageCode: String
    ) -> String {
        let fallback = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fallback.isEmpty else { return original }

        if let entry = entry(withID: entryID) {
            return entry.resolvedText(for: languageCode) ?? fallback
        }

        // Old data has no UUID link. A unique match across any configured
        // language lets it keep working until the user explicitly links it.
        if let entry = entry(matching: fallback) {
            return entry.resolvedText(for: languageCode) ?? fallback
        }

        return fallback
    }

    /// Returns the translation for the given language code, or the original string if not found.
    func translate(_ original: String, to languageCode: String) -> String {
        let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return original }

        if let entry = entry(matching: trimmed),
           let resolved = entry.resolvedText(for: languageCode) {
            return resolved
        }

        #if DEBUG
        print("⚠️ Missing '\(languageCode)' translation for: '\(trimmed)'")
        #endif
        return trimmed
    }

    // MARK: - Mutations

    func add(_ entry: TranslationEntry) {
        entries.append(entry)
        sort()
        save()
    }

    func update(_ entry: TranslationEntry) {
        if let i = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[i] = entry
        } else {
            entries.append(entry)
        }
        sort()
        save()
    }

    func delete(_ entry: TranslationEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    private func sort() {
        entries.sort { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    // MARK: - Seed from legacy hardcoded dictionaries

    private func seedFromLegacy() {
        var seeded: [String: [String: String]] = [:]

        // EN → PT (direct)
        let enToPt: [String: String] = [
            "Picture Editing": "Edição de Imagem",
            "Sound Edit Suite": "Sala Edição Som",
            "Color Grading Suite": "Sala Correção Cor",
            "ADR Recording": "Gravação de Dobragens",
            "Foley Stage": "Estúdio de Foley",
            "Film Edit Suite": "Sala Edição de Imagem",
            "Assistant Film Editor": "Assistente de Edição Imagem",
            "Film Editor": "Editor de Imagem",
            "Online Editor": "Editor Online",
            "Sound Editor": "Editor de Som",
            "Supervising Sound Editor": "Supervisor de Edição de Som",
            "Film Mixing Stage": "Estúdio de Mistura de Filmes",
            "TV Mix Studio 5.1/Atmos": "Estúdio Misturas TV (5.1/Atmos)",
            "TV Mix Studio Stereo": "Estúdio Misturas TV (Stereo)",
            "ADR Mixer": "Tec. Gravação de Dobragens",
            "Film Re-Recording Mixer": "Misturador de Som Cinema",
            "Foley Mixer": "Tec. Gravação de Foley",
            "TV Re'Recording Mixer 5.1/Atmos": "Misturador de Som TV (5.1/Atmos)",
            "TV Re'Recording Mixer Stereo": "Misturador de Som TV (Stereo)",
            "ADR Studio": "Estúdio Gravação de Dobragens",
            "Foley Studio": "Estúdio Gravação de Foley",
            "Conforming": "Edição Online",
            "Colorist": "Colorista",
            "Data Manager": "Gestor de Dados",
            "Foley Artist": "Artista de Foley",
            "Post-Production Supervisor": "Supervisor de Pós-Produção",
            "VAT Nº": "NIF",
            "Client": "Cliente",
            "Address": "Morada",
            "Email": "Email",
            "Phone": "Telefone",
            "Attention": "A/C",
            "Title": "Título",
            "Budget nº": "Orçamento nº",
            "Item": "Item",
            "Notes": "Notas",
            "Unit": "Unidade",
            "Qty": "Qt.",
            "Price": "Preço",
            "Total": "Total",
            "Subtotal": "Subtotal",
            "Discount": "Desconto",
            "Page": "Página",
            "Edit Suite": "Sala de Edição",
            "Studio Mix Theatrical": "Estúdio de Mistura Cinema",
            "Studio Mix Tv 5.1/Atmos HT": "Estúdio de Mistura TV 5.1/Atmos",
            "Studio Mix Tv Stereo": "Estúdio de Mistura TV Stereo",
            "Color Grading Suite Cinema": "Sala de Correção de Cor Cinema",
            "Color Grading Suite HDR": "Sala de Correção de Cor HDR",
            "Color Grading Suite TV": "Sala de Correção de Cor TV",
            "Protools Suite": "Sala Pro Tools",
            "Sound Recording": "Gravação de Som",
            "Foley Editor": "Editor de Foley",
            "PUB Editor": "Editor de PUB",
            "Re-Recording Mixer": "Misturador de Regravação",
            "Re-Recording Mixer Tv": "Misturador de Regravação TV",
            "Re-Recording TV Mixer 5.1/Atmos": "Misturador TV 5.1/Atmos",
        ]

        // PT → EN (flipped to EN key, PT translation)
        let ptToEn: [String: String] = [
            "Arquivo LTO 5": "Archiving to LTO-5 Drive",
            "Arquivo LTO 6": "Archiving to LTO-6 Drive",
            "Arquivo LTO 7": "Archiving to LTO-7 Drive",
            "Arquivo LTO 8": "Archiving to LTO-8 Drive",
            "Bluray - Encoding e Gravação": "Blu-ray Encoding & Burning",
            "DVD - Encoding e Gravação": "DVD Encoding & Burning",
            "Conversão de 24fps a 25fps": "24fps to 25fps Conversion",
            "Cópia DCP para Disco Externo": "DCP Copy to External Drive",
            "DCP Master 2K - Curta/Longa Metragem": "DCP Master 2K – Short / Feature",
            "DCP Master 4K - Curta/Longa Metragem": "DCP Master 4K – Short / Feature",
            "DCP Master 2K - Trailer/PUB": "DCP Master 2K – Trailer / Spot",
            "DCP Master 4K - Trailer/PUB": "DCP Master 4K – Trailer / Spot",
            "Entrega Digital - DCP PUB/Trailer": "Digital Delivery – DCP Trailer / Spot",
            "Entrega Prioritária (DCP) - No Dia": "Priority Delivery (DCP) – Same Day",
            "Entrega Prioritária (DCP) - 1 Dia": "Priority Delivery (DCP) – 1 Day",
            "Entrega Prioritária (DCP) - 2 Dias": "Priority Delivery (DCP) – 2 Days",
            "IMF Curta/Longa Metragem": "IMF Short / Feature",
            "IMF - Trailer/PUB": "IMF – Trailer / Spot",
            "Inserção Legenda DCP": "DCP Subtitle Insertion",
            "Inserção Legendas em Ficheiro": "File Subtitle Insertion",
            "KDM Isolado": "Single KDM",
            "KDM Complexo": "Complex KDM",
            "Master HD - Curta/Longa Metragem": "HD Master – Short / Feature",
            "Master HD - Trailer/PUB": "HD Master – Trailer / Spot",
            "Master 4K - Curta/Longa Metragem": "4K Master – Short / Feature",
            "Master 4K - Trailer/PUB": "4K Master – Trailer / Spot",
            "Normalização de Níveis Loudness": "Loudness Normalization",
            "Restore LTO para Disco": "LTO Restore to Disk",
            "TRANSFER A DNxHD OU ProRes": "Transfer to DNxHD or ProRes",
            "Teste Ingest Servidor DOREMI": "DOREMI Server Ingest Test",
            "Versioning File (DCP)": "DCP Versioning File",
        ]

        // Merge EN→PT (key is English)
        for (en, pt) in enToPt {
            seeded[en, default: [:]] ["pt"] = pt
        }

        // Merge PT→EN: key becomes the English value, PT translation is the original PT key
        for (pt, en) in ptToEn {
            seeded[en, default: [:]] ["pt"] = pt
        }

        // Section labels (used in budget export)
        let sectionLabels: [String: String] = [
            "Dailies":                        "Dailies",
            "Picture Editing":                "Edição de Imagem",
            "Sound Editing":                  "Edição de Som",
            "Sound Mixing":                   "Mistura de Som",
            "ADR – Recording & Editing":      "Dobragens – Gravação & Edição",
            "Foley – Recording & Editing":    "Foley – Gravação & Edição",
            "Color Grading":                  "Correção de Cor",
            "Deliveries":                     "Entregas",
            "Management":                     "Gestão",
            "Others":                         "Outros",
            // Footer notes
            "All amounts are subject to the applicable VAT rate.": "A todos os valores acresce a taxa de IVA em vigor.",
            "Offer valid for 30 days.":       "Validade da proposta 30 dias.",
            "Offer valid for {days} day.":    "Validade da proposta {days} dia.",
            "Offer valid for {days} days.":   "Validade da proposta {days} dias.",
            // Common units. These are editable defaults, not hardcoded output.
            "unit":                           "un.",
            "h":                              "h",
            "hour":                           "hora",
            "day":                            "dia",
            "minute":                         "minuto",
            "file":                           "ficheiro",
            "GB":                             "GB",
            "TB":                             "TB",
        ]
        for (en, pt) in sectionLabels {
            seeded[en, default: [:]] ["pt"] = pt
        }

        entries = seeded.map { key, translations in
            TranslationEntry(key: key, translations: translations)
        }
        sort()
        print("✅ Seeded \(entries.count) translation entries from legacy dictionaries")
    }
}

// MARK: - Convenience extension on ExportLanguage

extension ExportLanguage {
    var code: String { rawValue }  // already "en" / "pt"
}

