import Foundation
import SwiftData
import os

/// Opens the database, falling back so the app always starts.
enum CubbyStore {
    private static let log = Logger(subsystem: "Cubby", category: "store")

    static func makeContainer() -> ModelContainer {
        let schema = Schema([Entry.self])

        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-cubbyInMemory") || arguments.contains("-cubbyDemo") {
            let memory = ModelConfiguration("CubbyMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [memory]) {
                return container
            }
        }

        // 1. Synced through the user's private iCloud database (when the entitlement is present).
        do {
            let synced = ModelConfiguration("Cubby", schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: [synced])
        } catch {
            log.error("Synced store unavailable, using a local store: \(error.localizedDescription, privacy: .public)")
        }

        // 2. The same store without sync.
        do {
            let local = ModelConfiguration("Cubby", schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [local])
        } catch {
            log.error("Local store unavailable, using memory only: \(error.localizedDescription, privacy: .public)")
        }

        // 3. Last resort: nothing persists, but capture still works for this session.
        do {
            let memory = ModelConfiguration("CubbyMemory", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [memory])
        } catch {
            fatalError("Cubby could not open any data store: \(error)")
        }
    }
}
