//
//  QuoteTemplate.swift
//  Projector
//
//  Created by Branko Neskov on 15/11/2025.
//
import Foundation

struct QuoteTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String

    // Structure copied from a budget
    var lines: [BudgetLine]
    var discountPercent: Double
    var contingencyPercent: Double
    var exportLanguage: ExportLanguage
}
