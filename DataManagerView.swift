//
//  DataManagerView.swift
//  Projector
//
//  Created by Branko Neskov on 04/11/2025.
//
import SwiftUI
import AppKit

struct DataManagerView: View {
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var sessions: SessionStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var people: PeopleStore
    @EnvironmentObject private var rooms: RoomStore
    @EnvironmentObject private var clients: ClientsStore
    @EnvironmentObject private var roomCats: RoomCategoryStore
    @EnvironmentObject private var personCats: PersonCategoryStore
    @EnvironmentObject private var services: ServiceStore

    @State private var autoBackupFolder: URL? = DataBackup.autoBackupFolder
    @State private var lastBackupDate: Date? = DataBackup.lastAutoBackupDate
    @State private var backupInProgress = false
    @State private var backupStatusMessage: String? = nil
    @State private var showBackupFailureBanner = false
    @State private var backupFailureReason: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                // ── Backup failure banner ─────────────────────────────────
                if showBackupFailureBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-backup failed")
                                .font(.headline).foregroundColor(.white)
                            Text(backupFailureReason)
                                .font(.caption).foregroundColor(.white.opacity(0.85))
                        }
                        Spacer()
                        Button("Choose New Destination") {
                            showBackupFailureBanner = false
                            DataBackup.chooseAutoBackupFolder { url in
                                autoBackupFolder = url
                                if url != nil { runBackupNow() }
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)

                        Button {
                            showBackupFailureBanner = false
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.orange)
                    .cornerRadius(10)
                }

                Text("Data Management")
                    .font(.title2).bold()

                Text("Export all databases to a portable backup file, or import from a backup to replace your current data.")
                    .foregroundColor(.secondary)
                    .padding(.bottom, 6)

                // Manual export/import
                HStack(spacing: 12) {
                    Button {
                        DataBackup.exportAll()
                    } label: {
                        Label("Export All…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        DataBackup.importAll {
                            reloadAllStores()
                        }
                    } label: {
                        Label("Import…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                }

                Divider().padding(.vertical, 10)

                // ── Auto Backup ───────────────────────────────────────────
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {

                        // Status row
                        HStack(spacing: 8) {
                            Image(systemName: autoBackupFolder != nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundColor(autoBackupFolder != nil ? .green : .orange)
                            if let folder = autoBackupFolder {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(folder.path)
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if let last = lastBackupDate {
                                        Text("Last backup: \(last.formatted(date: .abbreviated, time: .shortened))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("No backup yet")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("No auto-backup folder configured")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        // Status message (success/error feedback)
                        if let msg = backupStatusMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(msg.hasPrefix("✅") ? .green : .red)
                        }

                        // Action buttons
                        HStack(spacing: 10) {
                            Button {
                                DataBackup.chooseAutoBackupFolder { url in
                                    autoBackupFolder = url
                                }
                            } label: {
                                Label(autoBackupFolder != nil ? "Change Folder…" : "Choose Folder…",
                                      systemImage: "folder")
                            }

                            if autoBackupFolder != nil {
                                Button {
                                    runBackupNow()
                                } label: {
                                    if backupInProgress {
                                        ProgressView().scaleEffect(0.7)
                                    } else {
                                        Label("Back Up Now", systemImage: "externaldrive.badge.checkmark")
                                    }
                                }
                                .disabled(backupInProgress)

                                Button(role: .destructive) {
                                    DataBackup.clearAutoBackupFolder()
                                    autoBackupFolder = nil
                                    backupStatusMessage = nil
                                } label: {
                                    Label("Remove", systemImage: "xmark.circle")
                                }
                            }
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Automatic Daily Backup", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                }

                Divider().padding(.vertical, 10)

                // ── Data folder ───────────────────────────────────────────
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Data Folder:")
                        .font(.headline)
                    Text(DataBackup.currentDataDirectory.path)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    HStack(spacing: 12) {
                        Button {
                            chooseDataFolder()
                        } label: {
                            Label("Change Data Folder…", systemImage: "folder")
                        }

                        Button(role: .destructive) {
                            resetToDefaultDataFolder()
                        } label: {
                            Label("Use Default Location", systemImage: "arrow.uturn.backward")
                        }
                        .help("Switch back to the standard Application Support/Projector folder.")
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 360)
        .onReceive(NotificationCenter.default.publisher(for: DataBackup.autoBackupFailedNotification)) { note in
            backupFailureReason = note.userInfo?["error"] as? String ?? "Backup destination unavailable."
            showBackupFailureBanner = true
        }
    }

    // MARK: - Auto backup

    private func runBackupNow() {
        backupInProgress = true
        backupStatusMessage = nil
        DataBackup.runAutoBackupNow { result in
            backupInProgress = false
            switch result {
            case .success(let url):
                lastBackupDate = DataBackup.lastAutoBackupDate
                backupStatusMessage = "✅ Backup saved: \(url.lastPathComponent)"
            case .failure(let error):
                backupStatusMessage = "❌ Backup failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Reload all stores after import
    private func reloadAllStores() {
        budgets.reload()
        sessions.reload()
        projects.reload()
        people.reload()
        rooms.reload()
        clients.reload()
        roomCats.reload()
        personCats.reload()
        services.reload()
    }

    // MARK: - Data folder selection

    /// Let the user choose a new base data folder (e.g. inside Google Drive / iCloud / Dropbox).
    private func chooseDataFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Data Folder"
        panel.message = "Select a folder where Projector will store its JSON data. You can pick a shared folder such as Google Drive, iCloud Drive, or Dropbox."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            // Save the custom folder path
            DataPaths.setCustomBaseURL(url)
            // Reload all stores so they read from the new location
            reloadAllStores()
        }
    }

    /// Reset the data folder back to the default Application Support location.
    private func resetToDefaultDataFolder() {
        DataPaths.clearCustomBaseURL()
        reloadAllStores()
    }
}
