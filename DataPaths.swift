//
//  DataPaths.swift
//  Projector
//
//  Created by Branko Neskov on 27/10/2025.
//
import Foundation

enum DataPaths {
    // change this to "Documents/ProjectorData" if you want a visible folder
    static let baseFolder = "Projector"

    static var baseURL: URL {
        let fm = FileManager.default
        let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSup.appendingPathComponent(baseFolder, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func file(_ name: String) -> URL {
        baseURL.appendingPathComponent(name)
    }

    /// One-time migration from the old "StudioSchedulerPeople" folder.
    static func migrateFromOldIfNeeded() {
        let fm = FileManager.default
        let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let oldDir = appSup.appendingPathComponent("StudioSchedulerPeople", isDirectory: true)
        let newDir = baseURL

        guard fm.fileExists(atPath: oldDir.path) else { return }
        do {
            let items = try fm.contentsOfDirectory(atPath: oldDir.path)
            for item in items where item.hasSuffix(".json") {
                let src = oldDir.appendingPathComponent(item)
                let dst = newDir.appendingPathComponent(item)
                if !fm.fileExists(atPath: dst.path) {
                    try fm.copyItem(at: src, to: dst) // or moveItem if you prefer
                }
            }
        } catch {
            print("Migration warning:", error)
        }
    }
}

