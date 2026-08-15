//
//  ServerSettingsView.swift
//  Projector
//
//  Panel for starting/stopping the Projector HTTP server and viewing status.
//

import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers

struct ServerSettingsView: View {
    @ObservedObject private var server = ProjectorServer.shared
    @ObservedObject private var auth = ServerAuth.shared
    @ObservedObject private var people = PeopleStore.shared
    @AppStorage("projector.server.autoStart") private var autoStart = false
    @State private var pushConfigurationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ───────────────────────────────────────────────────
            HStack {
                Text("Projector Server")
                    .font(.title2).bold()
                Spacer()
                statusBadge
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Connection info ──────────────────────────────────
                    GroupBox("Connection") {
                        VStack(alignment: .leading, spacing: 12) {
                            infoRow(label: "Local IP", value: server.localIPAddress)
                            infoRow(label: "Port", value: "\(server.port)")
                            infoRow(label: "Local URL",
                                    value: "http://\(server.localIPAddress):\(server.port)")

                            Divider()

                            HStack(spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                Text("For remote access, set up Cloudflare Tunnel pointing to the Local URL above.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(4)
                    }

                    // ── Technician access ────────────────────────────────
                    GroupBox("Projector Go Technician Access") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Create a short-lived pairing code for one technician. The code can be used once and expires after 15 minutes.")
                                .font(.callout)
                                .foregroundColor(.secondary)

                            Menu {
                                ForEach(activePeople) { person in
                                    Button(person.name) {
                                        _ = auth.createPairing(for: person)
                                    }
                                }
                            } label: {
                                Label("Create Pairing Code", systemImage: "key.fill")
                            }
                            .disabled(activePeople.isEmpty)

                            if let pairing = auth.activePairing {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Pairing \(pairing.personName)")
                                        .font(.callout.weight(.semibold))
                                    HStack(spacing: 8) {
                                        Text(pairing.code)
                                            .font(.system(.title3, design: .monospaced).weight(.semibold))
                                            .textSelection(.enabled)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(Color.blue.opacity(0.12),
                                                        in: RoundedRectangle(cornerRadius: 6))
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(pairing.code, forType: .string)
                                        } label: {
                                            Label("Copy", systemImage: "doc.on.doc")
                                        }
                                        .buttonStyle(.bordered)
                                        Button("Cancel") { auth.cancelPairing() }
                                            .buttonStyle(.bordered)
                                    }
                                    Text("Expires \(pairing.expiresAt.formatted(date: .omitted, time: .shortened)). Creating another code cancels this one.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(10)
                                .background(Color.blue.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 8))
                            }

                            if !pairedPeople.isEmpty {
                                Divider()
                                Text("Paired technicians")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                ForEach(pairedPeople) { person in
                                    HStack {
                                        Image(systemName: "checkmark.shield.fill")
                                            .foregroundColor(.green)
                                        Text(person.name)
                                        Spacer()
                                        Button("Revoke…", role: .destructive) {
                                            confirmRevoke(person)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        .padding(4)
                    }

                    GroupBox("Push Notifications") {
                        VStack(alignment: .leading, spacing: 10) {
                            pushStatusRow(
                                label: "iOS / APNs",
                                configured: FileManager.default.fileExists(
                                    atPath: DataPaths.secretFile("AuthKey_56GADA269T.p8").path
                                )
                            )
                            pushStatusRow(
                                label: "Android / Firebase",
                                configured: FileManager.default.fileExists(
                                    atPath: DataPaths.secretFile("firebase-service-account.json").path
                                )
                            )
                            HStack {
                                Button("Import APNs Key…") { importAPNsKey() }
                                    .buttonStyle(.bordered)
                                Button("Import Firebase Service Account…") { importFirebaseServiceAccount() }
                                    .buttonStyle(.bordered)
                            }
                            Text("Push credentials are stored locally on this Mac, outside the selectable Projector data folder.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let pushConfigurationMessage {
                                Text(pushConfigurationMessage)
                                    .font(.caption)
                                    .foregroundColor(pushConfigurationMessage.hasPrefix("Imported") ? .green : .red)
                            }
                        }
                        .padding(4)
                    }

                    // ── Controls ─────────────────────────────────────────
                    GroupBox("Controls") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Button(server.isRunning ? "Stop Server" : "Start Server") {
                                    if server.isRunning { server.stop() }
                                    else { server.start() }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(server.isRunning ? .red : .green)

                                if server.isRunning {
                                    Button("Restart") {
                                        server.stop()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            server.start()
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }

                            Toggle("Start server automatically when Projector launches", isOn: $autoStart)
                                .toggleStyle(.switch)
                                .onChange(of: autoStart) { _, newValue in
                                    // autoStart is handled in ProjectorApp.init()
                                }

                            if let error = server.lastError {
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(error)
                                        .foregroundColor(.red)
                                        .font(.callout)
                                }
                                .padding(8)
                                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                        .padding(4)
                    }

                    // ── Endpoints ────────────────────────────────────────
                    GroupBox("Available Endpoints") {
                        VStack(alignment: .leading, spacing: 8) {
                            endpointRow(method: "GET",  path: "/ping",                    desc: "Health check")
                            endpointRow(method: "POST", path: "/v1/pair", desc: "Exchange one-time pairing code")
                            endpointRow(method: "GET",  path: "/v1/me", desc: "Authenticated technician")
                            endpointRow(method: "GET",  path: "/v1/sessions?days=7", desc: "Technician's bookings only")
                            endpointRow(method: "GET",  path: "/v1/sessions/{id}/messages", desc: "Authorised message thread")
                            endpointRow(method: "POST", path: "/v1/sessions/{id}/messages", desc: "Append technician message")
                            endpointRow(method: "POST", path: "/v1/devices", desc: "Register this technician's device")
                        }
                        .padding(4)
                    }

                    // ── Request log ──────────────────────────────────────
                    GroupBox("Recent Requests") {
                        if server.requestLog.isEmpty {
                            Text("No requests yet")
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .padding(4)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(server.requestLog.prefix(20)) { entry in
                                    LogRow(entry: entry)
                                    if entry.id != server.requestLog.prefix(20).last?.id {
                                        Divider().opacity(0.4)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 560, minHeight: 500)
    }

    // MARK: - Subviews

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(server.isRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(server.isRunning ? "Running on port \(server.port)" : "Stopped")
                .font(.callout)
                .foregroundColor(server.isRunning ? .green : .secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background((server.isRunning ? Color.green : Color.secondary).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 20))
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var activePeople: [Person] {
        people.people
            .filter(\.isActive)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var pairedPeople: [Person] {
        activePeople.filter { auth.pairedPersonIDs.contains($0.id) }
    }

    private func confirmRevoke(_ person: Person) {
        let alert = NSAlert()
        alert.messageText = "Revoke \(person.name)'s Projector Go access?"
        alert.informativeText = "Their personal token and registered devices will stop working. Other technicians are unaffected."
        alert.addButton(withTitle: "Revoke")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            auth.revoke(person.id)
        }
    }

    private func pushStatusRow(label: String, configured: Bool) -> some View {
        HStack {
            Image(systemName: configured ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundColor(configured ? .green : .orange)
            Text(label)
            Spacer()
            Text(configured ? "Configured" : "Not configured")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func importAPNsKey() {
        guard let data = chooseFile(allowedExtensions: ["p8"]),
              let text = String(data: data, encoding: .utf8),
              text.contains("BEGIN PRIVATE KEY") else {
            pushConfigurationMessage = "The selected APNs key is not valid."
            return
        }
        do {
            try data.write(to: DataPaths.secretFile("AuthKey_56GADA269T.p8"), options: .atomic)
            pushConfigurationMessage = "Imported the APNs key."
        } catch {
            pushConfigurationMessage = "Could not save the APNs key."
        }
    }

    private func importFirebaseServiceAccount() {
        guard let data = chooseFile(allowedExtensions: ["json"]),
              let decoded = try? JSONSerialization.jsonObject(with: data),
              let object = decoded as? [String: Any],
              object["project_id"] is String,
              object["client_email"] is String,
              object["private_key"] is String else {
            pushConfigurationMessage = "The selected Firebase service-account file is not valid."
            return
        }
        do {
            try data.write(
                to: DataPaths.secretFile("firebase-service-account.json"),
                options: .atomic
            )
            pushConfigurationMessage = "Imported the Firebase service account."
        } catch {
            pushConfigurationMessage = "Could not save the Firebase service account."
        }
    }

    private func chooseFile(allowedExtensions: [String]) -> Data? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedExtensions.compactMap {
            UTType(filenameExtension: $0)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try? Data(contentsOf: url)
    }

    private func endpointRow(method: String, path: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Text(method)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(method == "GET" ? .blue : .orange)
                .frame(width: 36)
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background((method == "GET" ? Color.blue : Color.orange).opacity(0.1),
                            in: RoundedRectangle(cornerRadius: 4))
            Text(path)
                .font(.system(.callout, design: .monospaced))
            Text("–")
                .foregroundColor(.secondary)
            Text(desc)
                .foregroundColor(.secondary)
                .font(.callout)
        }
    }
}

// MARK: - Log Row

private struct LogRow: View {
    let entry: ServerLogEntry

    var statusColor: Color {
        switch entry.status {
        case 200, 201, 204: return .green
        case 404:      return .orange
        default:       return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(DateFormatter.localizedString(from: entry.time, dateStyle: .none, timeStyle: .medium))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(entry.method)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 36)

            Text(entry.path)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(entry.status)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(statusColor)
                .frame(width: 30)
        }
        .padding(.vertical, 4)
    }
}

