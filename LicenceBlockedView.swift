//
//  LicenceBlockedView.swift
//  Projector
//
//  Full-screen overlay shown when the trial or licence has expired.
//  Data is retained and accessible again once a licence is activated.
//

import SwiftUI

struct LicenceBlockedView: View {
    @ObservedObject private var licence = LicenceManager.shared
    @Environment(\.openWindow) private var openWindow

    @State private var keyInput = ""
    @State private var successMessage: String? = nil

    var body: some View {
        ZStack {
            // Frosted glass background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {

                    // Icon
                    Image(systemName: isTrialExpired ? "clock.badge.xmark" : "xmark.seal.fill")
                        .font(.system(size: 52))
                        .foregroundColor(.secondary)

                    // Title and message
                    VStack(spacing: 8) {
                        Text(isTrialExpired ? "Trial Period Ended" : "Licence Expired")
                            .font(.title).bold()
                        Text(isTrialExpired
                             ? "Your 15-day trial has ended. Activate a licence to continue using Projector.\nYour data is safe and will be accessible immediately after activation."
                             : "Your Projector licence has expired. Activate a new key to continue.\nYour data is safe and will be accessible immediately after activation.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                    }

                    // Success message
                    if let msg = successMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(msg).foregroundColor(.green)
                        }
                        .padding(12)
                        .background(Color.green.opacity(0.10))
                        .cornerRadius(8)
                    }

                    // Error message
                    if let error = licence.lastError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                            Text(error).foregroundColor(.red)
                        }
                        .padding(12)
                        .background(Color.red.opacity(0.10))
                        .cornerRadius(8)
                        .frame(maxWidth: 440)
                    }

                    // Key entry
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            TextField("Enter licence key", text: $keyInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                                .autocorrectionDisabled()
                                .frame(maxWidth: 320)
                                .onSubmit { activateKey() }

                            Button {
                                activateKey()
                            } label: {
                                if licence.isValidating {
                                    ProgressView().scaleEffect(0.8).frame(width: 80)
                                } else {
                                    Text("Activate")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(licence.isValidating || keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                        }

                        Link("Buy a licence →", destination: URL(string: "https://projectorapp.com/buy")!)
                            .font(.callout)
                    }
                }
                .padding(40)
                .background(.regularMaterial)
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)

                Spacer()
            }
            .padding(40)
        }
    }

    private var isTrialExpired: Bool {
        if case .trialExpired = licence.state { return true }
        return false
    }

    private func activateKey() {
        successMessage = nil
        licence.activate(key: keyInput) { result in
            if case .success = result {
                successMessage = "Licence activated! Welcome back."
                keyInput = ""
            }
        }
    }
}
