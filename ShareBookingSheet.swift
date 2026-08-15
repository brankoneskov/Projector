//
// ShareBookingSheet.swift
// Projector
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ShareBookingSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State var summary: String
    @State var location: String
    @State var start: Date
    @State var end: Date
    @State var descriptionText: String
    @State var attendees: [(name: String, email: String)] = []
    @State private var includeAttendees = true

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Export / Share Calendar Invite").font(.title3).bold()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            Form {
                TextField("Title", text: $summary)
                TextField("Location", text: $location)

                HStack {
                    DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $end, displayedComponents: [.date, .hourAndMinute])
                }

                Toggle("Include attendees", isOn: $includeAttendees)

                TextField("Description / Notes", text: $descriptionText, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)

                if includeAttendees && !attendees.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Will include as ATTENDEE:").font(.caption).foregroundColor(.secondary)
                        ForEach(attendees.indices, id: \.self) { i in
                            let a = attendees[i]
                            Text("• \(a.name.isEmpty ? a.email : a.name) <\(a.email)>")
                                .font(.callout).foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)
                }
            }

            HStack {
                Button("Save .ics…") { saveICS() }
                Button("Share…") { shareICS() }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 560)
    }

    private func buildICSData() -> Data {
        let atts = includeAttendees ? attendees : []
        return ICSBuilder.makeICS(
            summary: summary,
            start: start,
            end: end,
            location: location,
            description: descriptionText,
            attendees: atts
        )
    }

    private func saveICS() {
        let data = buildICSData()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .data]
        panel.nameFieldStringValue = safeFilename("\(summary).ics")
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func shareICS() {
        let data = buildICSData()
        guard let temp = try? ICSBuilder.writeTempICS(filename: safeFilename("\(summary).ics"), data: data) else { return }
        let picker = NSSharingServicePicker(items: [temp])
        if let window = NSApp.keyWindow, let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }

    private func safeFilename(_ s: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return s.components(separatedBy: invalid).joined(separator: "_")
    }
}
