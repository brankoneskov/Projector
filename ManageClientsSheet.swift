//
//  ManageClientsSheet.swift
//  Projector
//
//  Created by Branko Neskov on 27/10/2025.
//
import SwiftUI
import UniformTypeIdentifiers

struct ManageClientsSheet: View {
    @EnvironmentObject private var store: ClientsStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var notes = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var address = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Clients").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .keyboardShortcut("w", modifiers: [.command])
            }
            .padding(12)
            
            Button("Import CSV…") {
                importCSV()
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Client name", text: $name)
                TextField("Contact name", text: $contactName)
                TextField("Email", text: $email)
                TextField("Phone", text: $phone)
                TextField("Address", text: $address)
                TextField("Notes", text: $notes)

                Button("Add") {
                    let nm = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !nm.isEmpty else { return }
                    store.add(Client(
                        name: nm,
                        contactName: contactName,
                        email: email,
                        phone: phone,
                        address: address,
                        notes: notes
                    ))
                    name = ""; contactName = ""; email = ""; phone = ""; address = ""; notes = ""
                }
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .controlSize(.small)

            Divider()

            List {
                Section("Active") {
                    ForEach(store.clients.filter { $0.isActive }) { c in
                        ClientRow(client: c).environmentObject(store)
                    }
                }
                Section("Inactive") {
                    ForEach(store.clients.filter { !$0.isActive }) { c in
                        ClientRow(client: c).environmentObject(store)
                    }
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListRowHeight, 28)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 640, minHeight: 420)
    }
    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.commaSeparatedText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Read file (UTF-8, fall back to Windows CP1252); if both fail, bail.
        let text = (try? String(contentsOf: url, encoding: .utf8))
               ?? (try? String(contentsOf: url, encoding: .windowsCP1252))
               ?? ""
        guard !text.isEmpty else { return }

        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return }

        let delimiter = detectDelimiter(in: headerLine)
        let header = parseCSVRow(headerLine, delimiter: delimiter).map { normalizeHeader($0) }

        let idx = { (keys: [String]) -> Int? in
            for k in keys.map(normalizeHeader) {
                if let i = header.firstIndex(of: k) { return i }
            }
            return nil
        }

        let nameI     = idx(["name","client","company"])
        let contactI  = idx(["contact","contact name","contactname"])
        let emailI    = idx(["email","e-mail","mail"])
        let phoneI    = idx(["phone","telephone","tel"])
        let addressI  = idx(["address","addr"])
        let notesI    = idx(["notes","note","remarks","comment"])

        for (n, line) in lines.enumerated() where n > 0 {
            let cols = parseCSVRow(line, delimiter: delimiter)
            if cols.isEmpty { continue }

            func val(_ i: Int?) -> String {
                guard let i, i < cols.count else { return "" }
                return cols[i].trimmingCharacters(in: .whitespaces)
            }

            let client = Client(
                name:        !(nameI == nil && cols.indices.contains(0)) ? val(nameI)    : cols[0],
                contactName:  val(contactI ?? (cols.indices.contains(1) ? 1 : nil)),
                email:        val(emailI   ?? (cols.indices.contains(2) ? 2 : nil)),
                phone:        val(phoneI   ?? (cols.indices.contains(3) ? 3 : nil)),
                address:      val(addressI ?? (cols.indices.contains(4) ? 4 : nil)),
                notes:        val(notesI   ?? (cols.indices.contains(5) ? 5 : nil))
            )

            if !client.name.isEmpty { store.add(client) }
        }
    }

    /// Detect likely delimiter by counting candidates in the header line.
    private func detectDelimiter(in header: String) -> Character {
        let candidates: [Character] = [",",";","\t","|"]
        return candidates.max(by: { a, b in header.filter { $0 == a }.count < header.filter { $0 == b }.count }) ?? ","
    }

    /// Parse a single CSV line with quotes and the given delimiter.
    private func parseCSVRow(_ line: String, delimiter: Character) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        var it = line.makeIterator()

        while let ch = it.next() {
            if ch == "\"" {
                if inQuotes, let nxt = it.peek(), nxt == "\"" {
                    // Escaped quote inside quotes
                    cur.append("\"")
                    _ = it.next()
                } else {
                    inQuotes.toggle()
                }
            } else if ch == delimiter && !inQuotes {
                out.append(cur.trimmingCharacters(in: .whitespaces))
                cur = ""
            } else {
                cur.append(ch)
            }
        }
        out.append(cur.trimmingCharacters(in: .whitespaces))
        return out
    }

    /// Case/space-insensitive header normalization
    private func normalizeHeader(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .lowercased()
         .replacingOccurrences(of: "_", with: " ")
    }

    private func parseCSVRow(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }

 }
private extension String.Iterator {
    mutating func peek() -> Character? {
        var copy = self
        return copy.next()
    }
}


private struct ClientRow: View {
    @EnvironmentObject private var store: ClientsStore
    @State var client: Client
    @State private var editingName = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // Name (keeps your edit-toggle behavior)
            if editingName {
                TextField("Client", text: $client.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)
                    .onSubmit { persist() }
                    .onChange(of: client.name) { _,_ in persist() }
            } else {
                Text(client.name).bold()
                    .frame(minWidth: 180, alignment: .leading)
            }
            
            // Contact person
            TextField("Contact", text: $client.contactName)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140)
                .onSubmit { persist() }
                .onChange(of: client.contactName) { _,_ in persist() }
            
            // Email
            TextField("Email", text: $client.email)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
                .onSubmit { persist() }
                .onChange(of: client.email) { _,_ in persist() }
            
            // Phone
            TextField("Phone", text: $client.phone)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 120)
                .onSubmit { persist() }
                .onChange(of: client.phone) { _,_ in persist() }
            
            // Address
            TextField("Address", text: $client.address)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)
                .onSubmit { persist() }
                .onChange(of: client.address) { _,_ in persist() }
            
            // Notes
            TextField("Notes", text: $client.notes)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 220)
                .onSubmit { persist() }
                .onChange(of: client.notes) { _,_ in persist() }
            
            Spacer()
            
            Toggle("Active", isOn: Binding(
                get: { client.isActive },
                set: { v in client.isActive = v; persist() }
            ))
            .labelsHidden()
            
            Menu("•••") {
                Button(editingName ? "Stop Editing Name" : "Edit Name") {
                    editingName.toggle()
                    if !editingName { persist() }
                }
                Divider()
                Button("Delete", role: .destructive) { showDeleteConfirm = true }
            }
        }
        .padding(.vertical, 4)
        // ✅ confirmationDialog works reliably in List rows on macOS
        .confirmationDialog(
            "Delete Client?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.delete(client)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Deleting is undoable. Are you sure?")
        }
    }

    private func persist() { store.update(client) }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

