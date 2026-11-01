// Little Imprints — the baby ink-pad keepsake app.
// On-device only: no account, no server, no analytics (spec §8).

import SwiftUI

@main
struct LittleImprintsApp: App {
    @StateObject private var store = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
        }
        .onChange(of: scenePhase) { _, phase in
            // Flush the debounced save when the app leaves the
            // foreground, so a kill inside the debounce window
            // can't lose the last edit (review finding).
            if phase == .background || phase == .inactive {
                store.saveNow()
            }
        }
    }
}
