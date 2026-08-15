//
//  DataBackup.swift
//  Projector
//
//  Created by Branko Neskov on 04/11/2025.

import Foundation
import AppKit
import UniformTypeIdentifiers

/// A simple file-package we can export/import (Finder shows it as a single file).
/// Example: "ProjectorData.projectorbackup"
enum DataBackup {
    static let packageExtension = "projectorbackup"

    /// Per-record folders — this IS the live data architecture (V2).
    /// Every store in DataStores.swift / RoomModels.swift / CategoryModels.swift /
    /// ClientModels.swift / ServiceStore.swift / VacationsStore.swift / MessageStore.swift /
    /// InvoiceStore.swift / PaymentStore.swift reads and writes one of these folders.
    /// If you add a new per-record store, add its folder name here too.
    private static let folderNames: [String] = [
        "Sessions",
        "Projects",
        "People",
        "Rooms",
        "RoomCategories",
        "PersonCategories",
        "Clients",
        "Budgets",
        "Services",
        "ServiceBookings",
        "Vacations",
        "Messages",
        "Invoices",
        "Payments",
        "Meta"
    ]

    /// Standalone single-file stores still in active use (not per-record folders).
    private static let fileNames: [String] = [
        "translations.json",
        "quoteTemplates.json",
        "quoteCounters.json",
        "studio.json",
        "logo_custom.png"
    ]

    /// Legacy single-file stores from before the V2 per-record-folder migration.
    /// These are no longer written by the live app — each store only reads them once,
    /// on first launch, if its corresponding folder above doesn't exist yet.
    /// Included in backups purely as a safety net for installations that have never
    /// been opened since upgrading (so the migration can still happen from the backup).
    private static let legacyFileNames: [String] = [
        "projects.json",
        "people.json",
        "roomCategories.json",
        "personCategories.json",
        "rooms.json",
        "clients.json",
        "sessions.json",
        "budgets.json",
        "services.json",
        "serviceBookings.json"
    ]

    // Where the app keeps its live JSON files.
    // We infer the directory from the existing DataPaths.file(_:) helper.
    private static var dataDir: URL {
        DataPaths.file("projects.json").deletingLastPathComponent()
    }
    static var currentDataDirectory: URL { dataDir }
    /// Export: create a file-package and copy JSONs into it.
    static func exportAll() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.nameFieldStringValue = defaultBackupName()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [UTType(filenameExtension: packageExtension) ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try writeBackupPackage(to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSSound.beep()
                Swift.print("Export failed:", error)
                showAlert("Export Failed", "Could not create backup:\n\(error.localizedDescription)")
            }
        }
    }

    /// Import: choose either a .projectorbackup package OR a folder containing legacy *.json files.
    /// Also accepts picking a single legacy *.json file (we’ll treat its parent folder as the import source).
    static func importAll(reload: () -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true

        // Allow everything; we validate ourselves.
        panel.allowedContentTypes = []
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Import"

        if panel.runModal() == .OK, let pickedURL = panel.url {
            // If user picked a single JSON file, import from its parent folder
            let url: URL
            if pickedURL.pathExtension.lowercased() == "json" {
                url = pickedURL.deletingLastPathComponent()
            } else {
                url = pickedURL
            }

            // Confirm destructive replace
            let confirm = NSAlert()
            confirm.messageText = "Replace current data?"
            confirm.informativeText = "This will overwrite your current databases with the contents of:\n\(url.lastPathComponent)."
            confirm.alertStyle = .warning
            confirm.addButton(withTitle: "Replace")
            confirm.addButton(withTitle: "Cancel")
            if confirm.runModal() != .alertFirstButtonReturn { return }

            do {
                try importFrom(url: url)
                reload()
            } catch {
                NSSound.beep()
                Swift.print("Import failed:", error)
                showAlert("Import Failed", "Could not import backup:\n\(error.localizedDescription)")
            }
        }
    }



    // MARK: - Core I/O

    private static func writeBackupPackage(to packageURL: URL) throws {
        let fm = FileManager.default

        // Ensure correct extension
        var dst = packageURL
        if dst.pathExtension != packageExtension {
            dst.deletePathExtension()
            dst.appendPathExtension(packageExtension)
        }

        // Create/empty the package folder
        if fm.fileExists(atPath: dst.path) {
            try fm.removeItem(at: dst)
        }
        try fm.createDirectory(at: dst, withIntermediateDirectories: true)

        // Copy single-file stores
        for name in fileNames {
            let src = dataDir.appendingPathComponent(name)
            let dstFile = dst.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: dstFile)
            }
        }

        // Copy per-record folders
        for folder in folderNames {
            let src = dataDir.appendingPathComponent(folder, isDirectory: true)
            let dstFolder = dst.appendingPathComponent(folder, isDirectory: true)
            if fm.fileExists(atPath: src.path) {
                try fm.copyItem(at: src, to: dstFolder)
            }
        }

        // Copy legacy files if present (optional)
        for name in legacyFileNames {
            let src = dataDir.appendingPathComponent(name)
            let dstFile = dst.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dstFile.path) {
                try fm.copyItem(at: src, to: dstFile)
            }
        }


        // Add small metadata
        let meta = [
            "app": "Projector",
            "date": ISO8601DateFormatter().string(from: Date()),
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        ]
        let metaData = try JSONSerialization.data(withJSONObject: meta, options: [.prettyPrinted])
        try metaData.write(to: dst.appendingPathComponent("meta.json"), options: .atomic)
    }
    private enum ImportError: LocalizedError {
        case invalidSelection

        var errorDescription: String? {
            switch self {
            case .invalidSelection:
                return "Please select a .projectorbackup backup or a folder containing legacy JSON files."
            }
        }
    }


    private static func readBackupPackage(from packageURL: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: packageURL.path) else {
            throw NSError(domain: "DataBackup", code: 404, userInfo: [NSLocalizedDescriptionKey: "Backup not found"])
        }

        // Ensure data dir exists
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // Restore single-file stores
        for name in fileNames {
            let src = packageURL.appendingPathComponent(name)
            let dstFile = dataDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                if fm.fileExists(atPath: dstFile.path) { try fm.removeItem(at: dstFile) }
                try fm.copyItem(at: src, to: dstFile)
            }
        }

        // Restore per-record folders (replace entire folder)
        for folder in folderNames {
            let src = packageURL.appendingPathComponent(folder, isDirectory: true)
            let dstFolder = dataDir.appendingPathComponent(folder, isDirectory: true)
            if fm.fileExists(atPath: src.path) {
                if fm.fileExists(atPath: dstFolder.path) { try fm.removeItem(at: dstFolder) }
                try fm.copyItem(at: src, to: dstFolder)
            }
        }

        // Restore legacy files if present in the package (optional)
        for name in legacyFileNames {
            let src = packageURL.appendingPathComponent(name)
            let dstFile = dataDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                if fm.fileExists(atPath: dstFile.path) { try fm.removeItem(at: dstFile) }
                try fm.copyItem(at: src, to: dstFile)
            }
        }

    }
    private static func importFrom(url: URL) throws {
        if url.pathExtension.lowercased() == packageExtension {
            // New format: file-package
            try readBackupPackage(from: url)
            return
        }

        // Old format: folder of JSONs (or any folder the user picked)
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)

        guard isDir.boolValue else {
            throw NSError(
                domain: "DataBackup",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Please select a .\(packageExtension) backup or a folder containing legacy JSON files."]
            )
        }

        try readLegacyFolder(from: url)
    }

    /// Legacy folders contain plain files like "projects.json", "sessions.json", etc.
    private static func readLegacyFolder(from folderURL: URL) throws {
        let fm = FileManager.default

        // 1) Ensure data dir exists
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)

        // 2) VERY IMPORTANT:
        // Your new stores prefer per-item folders (e.g. Budgets/, Sessions/).
        // If those folders already exist, simply copying budgets.json/sessions.json won't be used.
        // So we remove those per-item folders to force a clean import.
        for folderName in folderNames {
            let p = dataDir.appendingPathComponent(folderName)
            if fm.fileExists(atPath: p.path) {
                try? fm.removeItem(at: p)
            }
        }

        // 3) Copy each known legacy file if present
        for name in legacyFileNames {
            let src = folderURL.appendingPathComponent(name)
            let dst = dataDir.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: src, to: dst)
            }
        }
    }

    private static func defaultBackupName() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return "ProjectorData-\(df.string(from: Date())).\(packageExtension)"
    }

    // MARK: - Auto Backup

    private static let autoBackupFolderKey  = "projector.autoBackup.folderBookmark"
    private static let lastAutoBackupKey    = "projector.autoBackup.lastDate"
    private static let maxAutoBackups       = 30
    private static let retryDelay: TimeInterval = 300   // 5 minutes

    /// Notification posted on the main thread when an auto-backup fails after retry.
    /// userInfo["error"] contains the error description string.
    static let autoBackupFailedNotification = Notification.Name("projector.autoBackup.failed")

    /// Prevents two backup operations running simultaneously.
    private static var isBackingUp = false
    private static let backupQueue = DispatchQueue(label: "projector.autoBackup", qos: .background)

    // MARK: - Public API

    /// The folder the user has chosen for automatic backups, resolved from a security-scoped bookmark.
    static var autoBackupFolder: URL? {
        guard let data = UserDefaults.standard.data(forKey: autoBackupFolderKey) else { return nil }
        var isStale = false
        return try? URL(resolvingBookmarkData: data,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale)
    }

    /// Last successful auto-backup date, for display in the UI.
    static var lastAutoBackupDate: Date? {
        UserDefaults.standard.object(forKey: lastAutoBackupKey) as? Date
    }

    /// Call on every app launch.
    /// - Skips silently if less than 24 hours have passed since the last successful backup.
    /// - Runs entirely on a background thread — never blocks the UI.
    /// - On failure, waits 5 minutes and retries once.
    /// - If the retry also fails, posts `autoBackupFailedNotification` on the main thread
    ///   so the UI can show a non-modal warning banner.
    static func scheduleAutoBackupIfNeeded() {
        guard let folder = autoBackupFolder else { return }
        let now = Date()
        if let last = lastAutoBackupDate,
           now.timeIntervalSince(last) < 86400 { return }   // backed up within 24 hours

        backupQueue.async {
            attemptBackup(to: folder, isRetry: false)
        }
    }

    /// Manual backup triggered by the user. Runs on the backup queue immediately.
    /// Calls completion on the main thread with either a success URL or an error.
    static func runAutoBackupNow(completion: @escaping (Result<URL, Error>) -> Void) {
        guard let folder = autoBackupFolder else {
            let err = NSError(domain: "DataBackup", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "No auto-backup folder configured."])
            DispatchQueue.main.async { completion(.failure(err)) }
            return
        }
        backupQueue.async {
            guard !isBackingUp else {
                // Another backup is already running — don't stack them
                let err = NSError(domain: "DataBackup", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "A backup is already in progress."])
                DispatchQueue.main.async { completion(.failure(err)) }
                return
            }
            isBackingUp = true
            defer { isBackingUp = false }

            let accessed = folder.startAccessingSecurityScopedResource()
            defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

            do {
                let url = try runAutoBackup(to: folder)
                DispatchQueue.main.async {
                    UserDefaults.standard.set(Date(), forKey: lastAutoBackupKey)
                    Swift.print("✅ Manual backup completed: \(url.lastPathComponent)")
                    completion(.success(url))
                }
            } catch {
                DispatchQueue.main.async {
                    Swift.print("❌ Manual backup failed: \(error)")
                    completion(.failure(error))
                }
            }
        }
    }

    /// Let the user choose the auto-backup folder. Saves a security-scoped bookmark.
    static func chooseAutoBackupFolder(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose Auto-Backup Folder"
        panel.message = "Projector will save a daily backup here automatically. Choose a folder on an external drive, iCloud Drive, or anywhere you like."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            if let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                     includingResourceValuesForKeys: nil,
                                                     relativeTo: nil) {
                UserDefaults.standard.set(bookmark, forKey: autoBackupFolderKey)
            }
            completion(url)
        } else {
            completion(nil)
        }
    }

    /// Remove the configured auto-backup folder.
    static func clearAutoBackupFolder() {
        UserDefaults.standard.removeObject(forKey: autoBackupFolderKey)
    }

    // MARK: - Private

    /// Attempt a backup. On failure, either retries after 5 minutes (first attempt)
    /// or posts the failure notification (retry attempt).
    private static func attemptBackup(to folder: URL, isRetry: Bool) {
        guard !isBackingUp else {
            Swift.print("⏭ Backup skipped — another backup is already running")
            return
        }
        isBackingUp = true
        defer { isBackingUp = false }

        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }

        do {
            let url = try runAutoBackup(to: folder)
            DispatchQueue.main.async {
                UserDefaults.standard.set(Date(), forKey: lastAutoBackupKey)
                Swift.print("✅ Auto-backup completed: \(url.lastPathComponent)")
            }
        } catch {
            Swift.print("⚠️ Auto-backup \(isRetry ? "retry " : "")failed: \(error)")
            if isRetry {
                // Both attempts failed — notify the UI
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: autoBackupFailedNotification,
                        object: nil,
                        userInfo: ["error": error.localizedDescription]
                    )
                }
            } else {
                // First failure — wait 5 minutes then retry
                Swift.print("⏳ Retrying auto-backup in \(Int(retryDelay / 60)) minutes...")
                backupQueue.asyncAfter(deadline: .now() + retryDelay) {
                    attemptBackup(to: folder, isRetry: true)
                }
            }
        }
    }

    @discardableResult
    private static func runAutoBackup(to folder: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        // Dated filename with time so multiple backups per day don't collide
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm"
        let name = "ProjectorData-\(df.string(from: Date())).\(packageExtension)"
        let dst = folder.appendingPathComponent(name)
        try writeBackupPackage(to: dst)

        // Prune: keep only the most recent maxAutoBackups
        let all = (try? fm.contentsOfDirectory(at: folder,
                                                includingPropertiesForKeys: [.creationDateKey],
                                                options: .skipsHiddenFiles)) ?? []
        let backups = all
            .filter { $0.pathExtension == packageExtension }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d1 > d2   // newest first
            }
        if backups.count > maxAutoBackups {
            for old in backups[maxAutoBackups...] {
                try? fm.removeItem(at: old)
            }
        }
        return dst
    }

    private static func showAlert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}



