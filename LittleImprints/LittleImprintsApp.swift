// Little Imprints — the baby ink-pad keepsake app.
// On-device only: no account, no server, no analytics (spec §8).

import SwiftUI

@main
struct LittleImprintsApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
    }
}
