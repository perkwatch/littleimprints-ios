// RootView.swift — the five rooms of the app: Make a Print, the
// Book, the Growth timeline, Pages, Settings.

import SwiftUI

enum AppTab: Hashable {
    case capture, book, timeline, pages, settings
}

struct RootView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var tab: AppTab = .capture
    @State private var showLoadError = false

    var body: some View {
        TabView(selection: $tab) {
            CaptureView(selectedTab: $tab)
                .tabItem { Label("Make a Print", systemImage: "hand.raised.fill") }
                .tag(AppTab.capture)
            KeepsakeBookView(selectedTab: $tab)
                .tabItem { Label("Book", systemImage: "book.closed.fill") }
                .tag(AppTab.book)
            TimelineView(selectedTab: $tab)
                .tabItem { Label("Growth", systemImage: "ruler.fill") }
                .tag(AppTab.timeline)
            PagesView(selectedTab: $tab)
                .tabItem { Label("Pages", systemImage: "rectangle.stack.fill") }
                .tag(AppTab.pages)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .tint(.inkPlum)
        .onAppear {
            if store.loadError != nil { showLoadError = true }
        }
        .alert("The keepsake book", isPresented: $showLoadError) {
            Button("OK") {}
        } message: {
            Text(store.loadError ?? "")
        }
    }
}
