//
//  MessagesWindowView.swift
//  Projector
//

import SwiftUI

struct MessagesWindowView: View {
    @ObservedObject private var messageStore = MessageStore.shared
    @ObservedObject private var alertStore   = AlertStore.shared
    @EnvironmentObject private var sessions:  SessionStore
    @EnvironmentObject private var projects:  ProjectStore
    @EnvironmentObject private var invoices:  InvoiceStore
    @EnvironmentObject private var payments:  PaymentStore
    @AppStorage("ProjectorUserInitials") private var userInitials: String = "Studio"
    @Environment(\.openWindow) private var openWindow

    @State private var selectedSessionID: UUID? = nil
    @State private var replyText: String = ""

    private var selectedThread: MessageThread? {
        guard let id = selectedSessionID else { return nil }
        return messageStore.thread(for: id)
    }

    private func session(for id: UUID) -> Session? {
        sessions.sessions.first(where: { $0.id == id })
    }

    private func sessionLabel(for id: UUID) -> String {
        guard let s = session(for: id) else { return "Session" }
        return "\(s.title) — \(s.room)"
    }

    private func sessionDate(for id: UUID) -> String {
        guard let s = session(for: id) else { return "" }
        return s.start.formatted(date: .abbreviated, time: .shortened)
    }

    var body: some View {
        HSplitView {
            // Left: alerts + thread list
            VStack(spacing: 0) {
                HStack {
                    Text("Messages").font(.headline)
                    Spacer()
                    if !alertStore.alerts.isEmpty {
                        Text("\(alertStore.alerts.count)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red, in: Capsule())
                    }
                    Button { messageStore.reload(); refreshAlerts() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain).help("Reload")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)

                Divider()

                List(selection: $selectedSessionID) {
                    if !alertStore.alerts.isEmpty {
                        Section {
                            ForEach(alertStore.alerts) { alert in
                                AlertRow(alert: alert) {
                                    switch alert.action {
                                    case .openFinance:
                                        openWindow(id: "finance")
                                    case .openProject(let id):
                                        openWindow(id: "projectDashboard", value: id)
                                    }
                                }
                            }
                        } header: {
                            Text("Alerts")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.red)
                        }
                    }

                    Section {
                        if messageStore.threads.isEmpty {
                            HStack {
                                Spacer()
                                Text("No messages yet")
                                    .font(.callout).foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        } else {
                            ForEach(messageStore.threads) { thread in
                                ThreadRow(
                                    thread: thread,
                                    label: sessionLabel(for: thread.sessionID),
                                    date: sessionDate(for: thread.sessionID)
                                )
                                .tag(thread.sessionID)
                            }
                        }
                    } header: {
                        Text("Conversations")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
                .listStyle(.inset)
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)

            // Right: conversation
            VStack(spacing: 0) {
                if let thread = selectedThread, let s = session(for: thread.sessionID) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionLabel(for: s.id)).font(.headline)
                        Text(sessionDate(for: s.id)).font(.caption).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 10)

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(thread.messages) { msg in
                                    MessageBubble(message: msg).id(msg.id)
                                }
                            }
                            .padding(16)
                        }
                        .onChange(of: thread.messages.count) { _, _ in
                            if let last = thread.messages.last {
                                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        .onAppear {
                            if let last = thread.messages.last {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 8) {
                        TextField("Reply…", text: $replyText, axis: .vertical)                            .textFieldStyle(.roundedBorder)
                            .lineLimit(1...4)
                            .onSubmit { sendReply() }
                        Button(action: sendReply) {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.return, modifiers: .command)
                    }
                    .padding(12)

                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48)).foregroundColor(.secondary)
                        Text("Select a conversation").foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 400)
        }
        .frame(minWidth: 700, minHeight: 480)
        .onAppear { refreshAlerts() }
    }

    private func sendReply() {
        let text = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = selectedSessionID else { return }
        let name = userInitials.isEmpty ? "Studio" : userInitials
        messageStore.sendMessage(sessionID: id, text: text, senderName: name)
        replyText = ""
    }

    private func refreshAlerts() {
        alertStore.refresh(
            projects: projects.projects,
            invoices: invoices.invoices,
            payments: payments.payments
        )
    }
}

// MARK: - Alert Row

private struct AlertRow: View {
    let alert: StudioAlert
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: alert.severity.icon)
                    .foregroundColor(alert.severity.color)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(alert.severity.color)
                        .lineLimit(1)
                    Text(alert.detail).textSelection(.enabled)
                        .font(.caption).foregroundColor(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4).padding(.vertical, 4)
        .background(alert.severity.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Thread Row

private struct ThreadRow: View {
    let thread: MessageThread
    let label: String
    let date: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(thread.hasUnreadFromTech ? Color.blue : Color.clear)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout.weight(thread.hasUnreadFromTech ? .semibold : .regular))
                    .lineLimit(1)
                if let last = thread.messages.last {
                    Text(last.text).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                Text(date).font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    private var isStudio: Bool { message.senderType == .studio }

    var body: some View {
        HStack {
            if isStudio { Spacer(minLength: 40) }
            VStack(alignment: isStudio ? .trailing : .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if !isStudio {
                        Text(message.senderName).font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    }
                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundColor(.secondary)
                    if isStudio {
                        Text(message.senderName).font(.caption.weight(.semibold)).foregroundColor(.secondary)
                    }
                }
                Text(message.text).textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(
                        isStudio ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .foregroundColor(isStudio ? .white : .primary)
            }
            if !isStudio { Spacer(minLength: 40) }
        }
    }
}
