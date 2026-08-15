//
//  AppConfig.swift
//  Projector
//
//  Created by Branko Neskov on 05/11/2025.
//
// AppConfig.swift
// Projector

import Foundation

enum RecurrenceMode: String, Codable {
    case legacy   // current behavior (virtual only)
    case hybrid   // virtual + near-term materialization + detach/split
}

struct RecurrenceHorizon: Codable {
    /// How many months ahead to consider when validating conflicts on recurring items
    var conflictCheckMonths: Int = 12
    /// How many days ahead to auto-materialize occurrences (hybrid)
    var materializeWindowDays: Int = 90
    /// How many months of already-past materialized occurrences to keep before pruning
    var pruneOlderThanMonths: Int = 12
}

struct AppConfig: Codable {
    var recurrenceMode: RecurrenceMode = .legacy
    var horizons = RecurrenceHorizon()
    
    // You can swap this to a persisted settings object later
    static var shared = AppConfig()
}

