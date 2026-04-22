// Virtual_Backup_BoxApp.swift
// Virtual Backup Box
//
// The app entry point. Configures the SwiftData model container with all four
// data models and injects it into the SwiftUI environment so every View and
// ViewModel in the app can access the shared database.

import SwiftUI
import SwiftData

@main
struct Virtual_Backup_BoxApp: App {

    /// The shared SwiftData container holding all four models.
    /// Configured once at launch; the same container is used for the entire
    /// app lifetime. isStoredInMemoryOnly is false — data persists to disk.
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            KnownTarget.self,
            KnownCard.self,
            CopySession.self,
            FileRecord.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
