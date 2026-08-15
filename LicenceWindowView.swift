//
//  LicenceWindowView.swift
//  Projector
//
//  Licence management window — accessible any time from the Projector menu.
//  Shows trial/licence status and allows activation and deactivation.
//

import SwiftUI

struct LicenceWindowView: View {
    @ObservedObject private var licence = LicenceManager.shared

    @State private var keyInput = ""
    @State private var showDeactivateConfirm = false
    @State private var successMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Header ────────────────────────────────────────────────────
            HStack(spacing: 14) {
                Image(systemName: statusIcon)
                    .font(.system(size: 32))
                    .foregroundColor(statusColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.title3).bold()
                    Text(statusSubtitle)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(20)
            .background(statusColor.opacity(0.08))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── Success message ───────────────────────────────────
                    if let msg = successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(msg).foregroundColor(.green)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // ── Error message ─────────────────────────────────────
                    if let error = licence.lastError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(error).foregroundColor(.red)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // ── Activate section (trial or expired) ───────────────
                    if case .trialExpired = licence.state { activateSection }
                    else if case .expired = licence.state { activateSection }
                    else if case .trial = licence.state { activateSection }
                    else if case .gracePeriod = licence.state { activateSection }

                    // ── Licensed section ──────────────────────────────────
                    if case .licensed = licence.state { licencedSection }
                    else if case .expiryWarning = licence.state { licencedSection }

                    Divider()

                    // ── Buy link ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Don't have a licence?")
                            .font(.headline)
                        Text("Purchase a licence from our website. Annual and perpetual options available.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                        Link("Buy Projector →", destination: URL(string: "https://projectorapp.com/buy")!)
                            .font(.callout)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 420)
    }

    // MARK: - Activate section

    private var activateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activate Licence")
                .font(.headline)
            Text("Enter the licence key you received after purchase.")
                .foregroundColor(.secondary)
                .font(.callout)

            HStack(spacing: 10) {
                TextField("XXXX-XXXX-XXXX-XXXX", text: $keyInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .onSubmit { activateKey() }

                Button {
                    activateKey()
                } label: {
                    if licence.isValidating {
                        ProgressView().scaleEffect(0.8).frame(width: 60)
                    } else {
                        Text("Activate")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(licence.isValidating || keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: - Licensed section

    private var licencedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active Licence")
                .font(.headline)

            if case .licensed(let expiry) = licence.state {
                if let expiry {
                    licenceDetailRow("Renews", expiry.formatted(date: .long, time: .omitted))
                } else {
                    licenceDetailRow("Type", "Perpetual — never expires")
                }
            } else if case .expiryWarning(let days) = licence.state {
                licenceDetailRow("Expires in", "\(days) day\(days == 1 ? "" : "s")")
                    .foregroundColor(.orange)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Moving to a new Mac?")
                    .font(.callout).bold()
                Text("Deactivate here first, then activate on your new machine.")
                    .font(.callout).foregroundColor(.secondary)
                Button("Deactivate on this Mac…") {
                    showDeactivateConfirm = true
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .alert("Deactivate Licence?", isPresented: $showDeactivateConfirm) {
            Button("Deactivate", role: .destructive) { deactivate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will deactivate Projector on this Mac. You can activate it on another machine afterwards.")
        }
    }

    private func licenceDetailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.callout)
    }

    // MARK: - Actions

    private func activateKey() {
        successMessage = nil
        licence.activate(key: keyInput) { result in
            switch result {
            case .success:
                successMessage = "Licence activated successfully. Thank you!"
                keyInput = ""
            case .failure:
                break // lastError is set by LicenceManager
            }
        }
    }

    private func deactivate() {
        licence.deactivate { result in
            switch result {
            case .success:
                successMessage = nil
                keyInput = ""
            case .failure:
                break
            }
        }
    }

    // MARK: - Status display helpers

    private var statusIcon: String {
        switch licence.state {
        case .trial:          return "clock"
        case .trialExpired:   return "clock.badge.xmark"
        case .licensed:       return "checkmark.seal.fill"
        case .expiryWarning:  return "exclamationmark.triangle"
        case .gracePeriod:    return "exclamationmark.triangle.fill"
        case .expired:        return "xmark.seal.fill"
        }
    }

    private var statusColor: Color {
        switch licence.state {
        case .trial:          return .blue
        case .trialExpired:   return .red
        case .licensed:       return .green
        case .expiryWarning:  return .orange
        case .gracePeriod:    return .orange
        case .expired:        return .red
        }
    }

    private var statusTitle: String {
        switch licence.state {
        case .trial(let days):         return "Trial — \(days) day\(days == 1 ? "" : "s") remaining"
        case .trialExpired:            return "Trial Expired"
        case .licensed(let expiry):
            return expiry == nil ? "Licenced — Perpetual" : "Licenced — Annual"
        case .expiryWarning: return "Licence Expiring Soon"
        case .gracePeriod:   return "Licence Expired — Grace Period"
        case .expired:                 return "Licence Expired"
        }
    }

    private var statusSubtitle: String {
        switch licence.state {
        case .trial(let days):
            return "Full access for \(days) more day\(days == 1 ? "" : "s"). Enter a key below to activate."
        case .trialExpired:
            return "Your trial has ended. Purchase a licence to continue using Projector."
        case .licensed(let expiry):
            if let expiry {
                return "Valid until \(expiry.formatted(date: .long, time: .omitted))."
            }
            return "Your perpetual licence is active."
        case .expiryWarning(let days):
            return "Renew your licence within \(days) day\(days == 1 ? "" : "s") to avoid interruption."
        case .gracePeriod(let days):
            return "Projector will stop working in \(days) day\(days == 1 ? "" : "s"). Please renew."
        case .expired:
            return "Your licence has expired. Enter a new key or repurchase to continue."
        }
    }
}

