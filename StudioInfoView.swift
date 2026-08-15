//
//  StudioInfoView.swift
//  Projector
//
//  Studio identity settings — name, address, contact details, logo.
//  Accessible from Setup → Studio Info…
//  All fields are used in quote PDF headers.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StudioInfoView: View {
    @ObservedObject private var store = StudioInfoStore.shared
    @State private var showLogoAlert = false
    @State private var logoFeedback: String? = nil
    @State private var logoFeedbackIsWarning = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            Text("Studio Info")
                .font(.title2).bold()
                .padding(.bottom, 4)
            Text("This information appears in the header of every quote PDF you export.")
                .foregroundColor(.secondary)
                .padding(.bottom, 20)

            // ── Logo section ──────────────────────────────────────────────
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 20) {
                        // Logo preview
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.secondary.opacity(0.08))
                                .frame(width: 160, height: 60)
                            if let img = store.customLogoImage {
                                Image(nsImage: img)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 156, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else if let bundleImg = NSImage(named: "logo") {
                                Image(nsImage: bundleImg)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 156, height: 56)
                                    .opacity(0.4)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        Text("Default logo")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .padding(2),
                                        alignment: .bottom
                                    )
                            } else {
                                VStack(spacing: 4) {
                                    Image(systemName: "photo")
                                        .foregroundColor(.secondary)
                                    Text("No logo")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Studio Logo")
                                .font(.headline)

                            // Dimensions hint
                            if let img = store.customLogoImage {
                                Text(String(format: "%.0f × %.0f pt", img.size.width, img.size.height))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            // Feedback message
                            if let feedback = logoFeedback {
                                HStack(spacing: 4) {
                                    Image(systemName: logoFeedbackIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                        .foregroundColor(logoFeedbackIsWarning ? .orange : .green)
                                        .font(.caption)
                                    Text(feedback)
                                        .font(.caption)
                                        .foregroundColor(logoFeedbackIsWarning ? .orange : .green)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            HStack(spacing: 8) {
                                Button(store.hasCustomLogo ? "Replace Logo…" : "Choose Logo…") {
                                    chooseLogo()
                                }
                                if store.hasCustomLogo {
                                    Button("Remove") {
                                        showLogoAlert = true
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.red)
                                }
                            }
                        }
                        Spacer()
                    }

                    // Requirements note
                    Text("PNG recommended · Landscape orientation · Max 600×200px · Displayed at 120×40pt in the quote header. Larger images are resized automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            } label: {
                Label("Logo", systemImage: "photo")
                    .font(.headline)
            }
            .padding(.bottom, 16)

            // ── Studio details ────────────────────────────────────────────
            GroupBox {
                VStack(spacing: 10) {
                    infoRow("Studio Name",  binding: $store.info.name,    placeholder: "e.g. Loudness Films")
                    infoRow("Address",      binding: $store.info.address,  placeholder: "Street, City, Country")
                    infoRow("Email",        binding: $store.info.email,    placeholder: "hello@yourstudio.com")
                    infoRow("Phone",        binding: $store.info.phone,    placeholder: "+351 xxx xxx xxx")
                    infoRow("Website",      binding: $store.info.website,  placeholder: "https://yourstudio.com")
                    infoRow("VAT Number",   binding: $store.info.vat,      placeholder: "PT123456789")

                    Divider()

                    HStack {
                        Text("Quote Validity")
                            .frame(width: 110, alignment: .trailing)
                            .foregroundColor(.secondary)
                            .font(.callout)
                        Stepper("\(store.info.quoteValidityDays) days",
                                value: $store.info.quoteValidityDays,
                                in: 1...365,
                                step: 1)
                            .fixedSize()
                        Text("— shown on every exported quote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(4)
            } label: {
                Label("Contact Details", systemImage: "building.2")
                    .font(.headline)
            }

            Spacer()

            // ── Save button ───────────────────────────────────────────────
            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    store.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.top, 16)
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 500)
        .alert("Remove Logo?", isPresented: $showLogoAlert) {
            Button("Remove", role: .destructive) { store.removeLogo() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The default bundled logo will be used instead.")
        }
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, binding: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .frame(width: 110, alignment: .trailing)
                .foregroundColor(.secondary)
                .font(.callout)
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
                .onSubmit { store.save() }
        }
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.title = "Choose Studio Logo"
        panel.allowedContentTypes = [.png, .jpeg]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            let result = store.setLogo(from: url)
            switch result {
            case .accepted(let size):
                logoFeedback = String(format: "Logo accepted (%.0f × %.0f pt)", size.width, size.height)
                logoFeedbackIsWarning = false
            case .resized(let original, let new):
                logoFeedback = String(format: "Resized from %.0f×%.0f to %.0f×%.0f pt to fit the 600×200px limit.", original.width, original.height, new.width, new.height)
                logoFeedbackIsWarning = false
            case .portraitWarning(let size):
                logoFeedback = String(format: "Logo accepted (%.0f × %.0f pt), but landscape orientation works better in the quote header.", size.width, size.height)
                logoFeedbackIsWarning = true
            case .invalidFormat:
                logoFeedback = "Could not read the image. Please use a PNG or JPEG file."
                logoFeedbackIsWarning = true
            case .tooLarge:
                logoFeedback = "File is too large to process. Please use an image under 2MB."
                logoFeedbackIsWarning = true
            }
        }
    }
}
