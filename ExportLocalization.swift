//
// ExportLocalization.swift
// Projector
//
// Translation for PDF exports. All lookups now go through TranslationStore,
// which reads from a user-editable JSON file on disk.
//

import Foundation

/// Returns the label in the desired export language.
/// Falls back to the original string if no translation is found.
func localizedExportLabel(_ original: String, language: ExportLanguage) -> String {
    let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return original }
    guard language.code != "en" else { return trimmed }
    return TranslationStore.shared.translate(trimmed, to: language.code)
}

// MARK: - Budget section labels

func localizedSectionLabel(_ section: BudgetSection, language: ExportLanguage) -> String {
    guard language.code != "en" else { return section.label }

    // Section labels are fixed — translate them directly
    switch section {
    case .dailies:                return localizedExportLabel("Dailies",                          language: language)
    case .pictureEditing:         return localizedExportLabel("Picture Editing",                  language: language)
    case .soundEditing:           return localizedExportLabel("Sound Editing",                    language: language)
    case .soundMixing:            return localizedExportLabel("Sound Mixing",                     language: language)
    case .ADRRecordingEditing:    return localizedExportLabel("ADR – Recording & Editing",        language: language)
    case .FoleyRecordingEditing:  return localizedExportLabel("Foley – Recording & Editing",      language: language)
    case .ColorGrading:           return localizedExportLabel("Color Grading",                    language: language)
    case .deliveries:             return localizedExportLabel("Deliveries",                       language: language)
    case .management:             return localizedExportLabel("Management",                       language: language)
    case .others:                 return localizedExportLabel("Others",                           language: language)
    }
}

// MARK: - Export footer notes

func localizedExportFooterNotes(language: ExportLanguage) -> [String] {
    let days = StudioInfoStore.shared.info.quoteValidityDays
    let validityString = "Offer valid for \(days) day\(days == 1 ? "" : "s")."
    return [
        localizedExportLabel("All amounts are subject to the applicable VAT rate.", language: language),
        localizedExportLabel(validityString, language: language)
    ]
}
