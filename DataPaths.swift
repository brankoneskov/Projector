//
//  DataPaths.swift
//  Projector
//
//  Created by Branko Neskov on 27/10/2025.
//

import Foundation

enum DataPaths {
    /// Folder name used when no custom folder is chosen.
    private static let defaultFolderName = "Projector"

    /// UserDefaults key where we remember a custom base folder path.
    private static let customFolderKey = "Projector.CustomDataFolder"

    /// The base directory for all JSON files.
    ///
    /// - If the user has chosen a custom folder (e.g. a Dropbox folder), we use that.
    /// - Otherwise we fall back to ~/Library/Application Support/Projector.
    static var baseURL: URL {
        let fm = FileManager.default
        let defaults = UserDefaults.standard

        // 1) If a custom folder was chosen before, use it
        if let storedPath = defaults.string(forKey: customFolderKey),
           !storedPath.isEmpty {
            let url = URL(fileURLWithPath: storedPath, isDirectory: true)
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        // 2) Fallback: Application Support / Projector
        let appSup = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSup.appendingPathComponent(defaultFolderName, isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Return a specific JSON file inside the baseURL.
    static func file(_ name: String) -> URL {
        baseURL.appendingPathComponent(name)
    }
    /// Return (and create if needed) a subfolder inside baseURL.
    static func folder(_ name: String) -> URL {
        let fm = FileManager.default
        let url = baseURL.appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Operational/private data stays local to this Mac even when the user's
    /// ordinary Projector data folder is Dropbox or another synced location.
    static func privateFolder(_ name: String) -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport
            .appendingPathComponent(defaultFolderName, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Sensitive service credentials are never placed in the selectable data
    /// folder and are never exposed by ProjectorServer.
    static func secretFile(_ name: String) -> URL {
        privateFolder("Secrets").appendingPathComponent(name, isDirectory: false)
    }

    /// Remember a new custom base folder (e.g. a Dropbox folder).
    /// Call this when the user picks a folder in the Data Manager.
    static func setCustomBaseURL(_ folder: URL) {
        let fm = FileManager.default
        var dir = folder

        // If the user picked a file instead of a folder, use its parent folder.
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: dir.path, isDirectory: &isDir), !isDir.boolValue {
            dir.deleteLastPathComponent()
        }

        // Ensure the directory exists
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        UserDefaults.standard.set(dir.path, forKey: customFolderKey)
    }

    /// Clear the custom folder and go back to the default Application Support location.
    static func clearCustomBaseURL() {
        UserDefaults.standard.removeObject(forKey: customFolderKey)
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

