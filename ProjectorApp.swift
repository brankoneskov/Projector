//
// ProjectorApp.swift
// Projector
//

import SwiftUI
import Combine

@main
struct ProjectorApp: App {
    init() {
        DataPaths.migrateFromOldIfNeeded()
        DataBackup.scheduleAutoBackupIfNeeded()
        LicenceManager.shared.checkOnLaunch()

        // Show licence window on first launch or when trial is low
        let shownKey = "projector.licence.shownOnLaunch"
        let alreadyShown = UserDefaults.standard.bool(forKey: shownKey)
        let isLowTrial: Bool = {
            if case .trial(let days) = LicenceManager.shared.state { return days <= 3 }
            return false
        }()
        if !alreadyShown || isLowTrial {
            if !alreadyShown { UserDefaults.standard.set(true, forKey: shownKey) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                NotificationCenter.default.post(
                    name: Notification.Name("projector.openLicenceWindow"),
                    object: nil
                )
            }
        }
    }

    // Called after @AppStorage is available
    private func startServerIfNeeded() {
        if UserDefaults.standard.bool(forKey: "projector.server.autoStart") {
            ProjectorServer.shared.start()
        }
    }


    @StateObject private var budgetStore       = BudgetStore.shared
    @StateObject private var store             = SessionStore.shared
    @StateObject private var projects          = ProjectStore.shared
    @StateObject private var people            = PeopleStore.shared
    @StateObject private var roomsStore        = RoomStore.shared
    @StateObject private var filters           = Filters()
    @StateObject private var roomCategories    = RoomCategoryStore.shared
    @StateObject private var personCategories  = PersonCategoryStore.shared
    @StateObject private var clientsStore      = ClientsStore.shared
    @StateObject private var invoiceStore      = InvoiceStore.shared
    @StateObject private var paymentStore      = PaymentStore.shared
    @StateObject var services                  = ServiceStore.shared
    @StateObject private var messageStore      = MessageStore.shared
    @StateObject private var alertStore        = AlertStore.shared
    @StateObject private var server            = ProjectorServer.shared
    @StateObject private var licence           = LicenceManager.shared
    @StateObject private var studioInfo        = StudioInfoStore.shared

    /// Fires every hour to check whether a daily backup is due.
    /// Handles the case where the app runs continuously (e.g. studio iMac running 24/7)
    /// and is never restarted, so the launch-time check alone would never fire again.
    private let backupCheckTimer = Timer.publish(every: 3600, tolerance: 60, on: .main, in: .common).autoconnect()

    @AppStorage("projector.server.autoStart") private var autoStart = false

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .onAppear {
                    startServerIfNeeded()
                }
                .onReceive(backupCheckTimer) { _ in
                    DataBackup.scheduleAutoBackupIfNeeded()
                    LicenceManager.shared.revalidateIfNeeded()
                }
                .overlay {
                    if !licence.isAppFunctional {
                        LicenceBlockedView()
                    }
                }
                .environmentObject(budgetStore)
                .environmentObject(store)
                .environmentObject(projects)
                .environmentObject(people)
                .environmentObject(roomsStore)
                .environmentObject(filters)
                .environmentObject(roomCategories)
                .environmentObject(personCategories)
                .environmentObject(clientsStore)
                .environmentObject(services)
        }

        WindowGroup(id: "projects") {
            ManageProjectsSheet()
                .environmentObject(projects)
                .environmentObject(roomsStore)
                .environmentObject(clientsStore)
                .environmentObject(services)
        }

        WindowGroup("Project", id: "projectDashboard", for: UUID.self) { $projectID in
            if let id = projectID,
               let proj = projects.projects.first(where: { $0.id == id }) {
                ProjectDashboardView(project: proj)
                    .environmentObject(store)
                    .environmentObject(projects)
                    .environmentObject(people)
                    .environmentObject(roomsStore)
                    .environmentObject(roomCategories)
                    .environmentObject(personCategories)
                    .environmentObject(services)
                    .environmentObject(clientsStore)
            } else {
                Text("No project selected").frame(minWidth: 420, minHeight: 320)
            }
        }

        WindowGroup(id: "peopleManager") {
            ManagePeopleSheet()
                .environmentObject(people)
                .environmentObject(personCategories)
        }

        WindowGroup(id: "rooms") {
            ManageRoomsSheet()
                .environmentObject(roomsStore)
                .environmentObject(roomCategories)
        }

        WindowGroup(id: "roomCategories") {
            ManageRoomCategoriesView()
                .environmentObject(roomCategories)
        }

        WindowGroup(id: "personCategories") {
            ManagePersonCategoriesView()
                .environmentObject(personCategories)
        }

        WindowGroup("Budgets", id: "budget", for: UUID.self) { $projectID in
            if let id = projectID,
               projects.projects.first(where: { $0.id == id }) != nil {
                BudgetManagerView(projectID: id)
                    .environmentObject(budgetStore)
                    .environmentObject(projects)
                    .environmentObject(roomsStore)
                    .environmentObject(roomCategories)
                    .environmentObject(personCategories)
            } else {
                Text("No project selected").frame(minWidth: 420, minHeight: 320)
            }
        }

        WindowGroup(id: "services") {
            ServicesView().environmentObject(services)
        }

        .defaultSize(width: 920, height: 640)
        .windowResizability(.automatic)

        WindowGroup(id: "clients") {
            ManageClientsSheet().environmentObject(clientsStore)
        }

        WindowGroup(id: "dataManager") {
            DataManagerView()
                .environmentObject(BudgetStore.shared)
                .environmentObject(SessionStore.shared)
                .environmentObject(ProjectStore.shared)
                .environmentObject(PeopleStore.shared)
                .environmentObject(RoomStore.shared)
                .environmentObject(ClientsStore.shared)
                .environmentObject(RoomCategoryStore.shared)
                .environmentObject(PersonCategoryStore.shared)
                .environmentObject(ServiceStore.shared)
        }

        WindowGroup("Finances", id: "finance") {
            FinanceWindowView()
                .environmentObject(projects)
                .environmentObject(invoiceStore)
                .environmentObject(paymentStore)
        }

        WindowGroup("Messages", id: "messages") {
            MessagesWindowView()
                .environmentObject(store)
                .environmentObject(projects)
                .environmentObject(invoiceStore)
                .environmentObject(paymentStore)
        }

        WindowGroup("Server", id: "server") {
            ServerSettingsView()
        }

        WindowGroup("Translations", id: "translations") {
            TranslationsView()
        }

        WindowGroup("Statistics", id: "statistics") {
            StatisticsWindowView()
        }
        .defaultSize(width: 960, height: 700)

        WindowGroup("Studio Info", id: "studioInfo") {
            StudioInfoView()
        }
        .defaultSize(width: 540, height: 520)

        WindowGroup("Licence", id: "licence") {
            LicenceWindowView()
        }
        .defaultSize(width: 480, height: 420)
        .windowResizability(.contentSize)

        .commands {

            // ── File ─────────────────────────────────────────────────────
            CommandGroup(replacing: .newItem) {
                Button("New Session") { }
                    .keyboardShortcut("n", modifiers: [.command])
            }

            // ── Edit — remove text-editing commands irrelevant to a scheduling app ──
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .toolbar) { }

            // ── Licence — added to Help menu area ─────────────────────────
            CommandGroup(after: .appInfo) {
                Button("Licence…") { openWindow(id: "licence") }
                Divider()
            }

            // ── View — injected into the system View menu ─────────────────
            CommandGroup(after: .toolbar) {
                Divider()
                Button("List") {
                    NotificationCenter.default.post(name: Notification.Name("projector.setViewMode"), object: "list")
                }
                .keyboardShortcut("l", modifiers: [])

                Button("Day Timeline") {
                    NotificationCenter.default.post(name: Notification.Name("projector.setViewMode"), object: "timeline")
                }
                .keyboardShortcut("d", modifiers: [])

                Button("Week Timeline") {
                    NotificationCenter.default.post(name: Notification.Name("projector.setViewMode"), object: "week")
                }
                .keyboardShortcut("w", modifiers: [])

                Divider()

                Button("Go to Today") {
                    NotificationCenter.default.post(name: Notification.Name("projector.goToToday"), object: nil)
                }
                .keyboardShortcut("t", modifiers: [])

                Divider()

                Button(UserDefaults.standard.bool(forKey: "projector.timeline.lightMode")
                       ? "Timeline: Switch to Dark"
                       : "Timeline: Switch to Light") {
                    let current = UserDefaults.standard.bool(forKey: "projector.timeline.lightMode")
                    UserDefaults.standard.set(!current, forKey: "projector.timeline.lightMode")
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            }

            // ── Schedule ─────────────────────────────────────────────────
            CommandMenu("Schedule") {
                Button("Projects")    { openWindow(id: "projects") }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Rooms")       { openWindow(id: "rooms") }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("People")      { openWindow(id: "peopleManager") }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Clients")     { openWindow(id: "clients") }
                    .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button("Finance")     { openWindow(id: "finance") }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Messages…")   { openWindow(id: "messages") }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Statistics…") { openWindow(id: "statistics") }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            // ── Setup ─────────────────────────────────────────────────────
            CommandMenu("Setup") {
                Button("Studio Info…")         { openWindow(id: "studioInfo") }
                    .keyboardShortcut("b", modifiers: [.command, .shift])

                Divider()

                Button("Services…")        { openWindow(id: "services") }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Translations…")    { openWindow(id: "translations") }
                    .keyboardShortcut("t", modifiers: [.command, .shift])

                Divider()

                Button("Data Management…") { openWindow(id: "dataManager") }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Server…")          { openWindow(id: "server") }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
        }
    }
}
