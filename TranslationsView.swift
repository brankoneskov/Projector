//
//  TranslationsView.swift
//  Projector
//
//  Multi-language translation table. English is the key (source).
//  All other ExportLanguage cases are shown as editable columns.
//

import SwiftUI

// Non-English languages available for translation
private let translationLanguages: [ExportLanguage] = ExportLanguage.allCases.filter { $0 != .english }

struct TranslationsView: View {
    @ObservedObject private var store = TranslationStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var editingEntry: TranslationEntry? = nil
    @State private var newKey: String = ""
    @State private var newTranslations: [String: String] = [:]

    private var filtered: [TranslationEntry] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return store.entries }
        return store.entries.filter {
            $0.key.lowercased().contains(q) ||
            $0.translations.values.contains { $0.lowercased().contains(q) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translations").font(.title2).bold()
                    Text("\(store.entries.count) entries · English → \(translationLanguages.map { $0.fullName }.joined(separator: ", "))")
                        .font(.callout).foregroundColor(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)

            Divider()

            // ── Add new row ───────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                Text("NEW ENTRY")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .kerning(0.5)

                HStack(spacing: 8) {
                    TextField("English (required)", text: $newKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 180)

                    ForEach(translationLanguages, id: \.id) { lang in
                        TextField(lang.fullName, text: Binding(
                            get: { newTranslations[lang.rawValue] ?? "" },
                            set: { newTranslations[lang.rawValue] = $0.isEmpty ? nil : $0 }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }

                    Button("Add") {
                        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { return }
                        var translations: [String: String] = [:]
                        for lang in translationLanguages {
                            if let val = newTranslations[lang.rawValue],
                               !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                translations[lang.rawValue] = val.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        if let existing = store.entries.first(where: {
                            $0.key.caseInsensitiveCompare(key) == .orderedSame
                        }) {
                            var updated = existing
                            for (k, v) in translations { updated.translations[k] = v }
                            store.update(updated)
                        } else {
                            store.add(TranslationEntry(key: key, translations: translations))
                        }
                        newKey = ""; newTranslations = [:]
                    }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.primary.opacity(0.03))

            Divider()

            // ── Column headers ────────────────────────────────────────────
            HStack(spacing: 0) {
                Text("English")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)

                ForEach(translationLanguages, id: \.id) { lang in
                    Divider().frame(height: 24)
                    Text(lang.fullName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                }

                Divider().frame(height: 24)
                Text("Actions")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 80)
                    .padding(.horizontal, 12)
            }
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))

            Divider()

            List {
                ForEach(filtered) { entry in
                    TranslationRow(entry: entry, editingID: $editingEntry)
                }
            }
            .listStyle(.inset)
            .searchable(text: $searchText, prompt: "Search translations…")
        }
        .frame(minWidth: 900, minHeight: 500)
    }
}

// MARK: - Row

// MARK: - Row with inline editing (avoids nested sheet clipboard issues)

private struct TranslationRow: View {
    @ObservedObject private var store = TranslationStore.shared
    let entry: TranslationEntry
    @Binding var editingID: TranslationEntry?

    @State private var editKey: String = ""
    @State private var editTranslations: [String: String] = [:]
    @State private var showDeleteConfirm = false

    private var isEditing: Bool { editingID?.id == entry.id }

    var body: some View {
        Group {
            if isEditing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("English").font(.caption).foregroundColor(.secondary)
                            TextField("English", text: $editKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        .frame(minWidth: 180, maxWidth: .infinity)
                        .padding(.horizontal, 12)

                        ForEach(translationLanguages, id: \.id) { lang in
                            Divider().frame(height: 52)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lang.fullName).font(.caption).foregroundColor(.secondary)
                                TextField(lang.fullName, text: Binding(
                                    get: { editTranslations[lang.rawValue] ?? "" },
                                    set: { editTranslations[lang.rawValue] = $0.isEmpty ? nil : $0 }
                                ))
                                .textFieldStyle(.roundedBorder)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                        }

                        Divider().frame(height: 52)
                        HStack(spacing: 6) {
                            Button("Save") {
                                var updated = entry
                                updated.key = editKey.trimmingCharacters(in: .whitespacesAndNewlines)
                                for lang in translationLanguages {
                                    let val = (editTranslations[lang.rawValue] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                                    updated.translations[lang.rawValue] = val.isEmpty ? nil : val
                                }
                                store.update(updated)
                                editingID = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(editKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Button("Cancel") { editingID = nil }
                                .controlSize(.small)
                        }
                        .frame(width: 110)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(6)
            } else {
                HStack(spacing: 0) {
                    Text(entry.key)
                        .textSelection(.enabled)
                        .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)

                    ForEach(translationLanguages, id: \.id) { lang in
                        Divider().frame(height: 20)
                        let val = entry.translations[lang.rawValue]
                        Text(val ?? "—")
                            .textSelection(.enabled)
                            .foregroundColor(val == nil || val!.isEmpty ? .secondary : .primary)
                            .italic(val == nil || val!.isEmpty)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                    }

                    Divider().frame(height: 20)

                    HStack(spacing: 8) {
                        Button("Edit") {
                            editKey = entry.key
                            editTranslations = entry.translations
                            editingID = entry
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                    .frame(width: 80)
                    .padding(.horizontal, 8)
                }
                .padding(.vertical, 2)
                .confirmationDialog("Delete this entry?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { store.delete(entry) }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("\"\(entry.key)\" will be removed from translations.")
                }
            }
        }
    }
}
