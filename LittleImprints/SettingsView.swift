// SettingsView.swift — profiles, the capture toggles, the backup
// choice, Nightstand Walk, and the privacy posture in plain words
// (spec §1, §5, §8). Everything autosaves.

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var showNightstand = false
    @State private var newChildName = ""
    @State private var newChildBirth = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.paperCream.ignoresSafeArea()
                Form {
                    childrenSection
                    captureSection
                    librarySection
                    nightstandSection
                    privacySection
                    aboutSection
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showNightstand) {
                NightstandWalkView()
            }
        }
    }

    // MARK: Children

    private var childrenSection: some View {
        Section {
            ForEach(store.library.children) { child in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(child.name)
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.inkSoft)
                        Spacer()
                        if store.activeChild?.id == child.id {
                            Label("This book", systemImage: "checkmark.circle.fill")
                                .font(.system(.footnote, design: .rounded))
                                .foregroundColor(.inkPlum)
                        } else {
                            Button("Open this book") { store.setActiveChild(child.id) }
                                .font(.system(.footnote, design: .rounded))
                        }
                    }
                    DatePicker("Birthday", selection: birthBinding(child),
                               in: ...Date(), displayedComponents: .date)
                        .font(.system(.subheadline, design: .rounded))
                    Text(child.ageText(at: Date()))
                        .font(.footnote)
                        .foregroundColor(.inkFaint)
                }
                .padding(.vertical, 4)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Add another child")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.inkSoft)
                TextField("Name", text: $newChildName)
                DatePicker("Birthday", selection: $newChildBirth, in: ...Date(),
                           displayedComponents: .date)
                    .font(.system(.subheadline, design: .rounded))
                Button("Add") {
                    let name = newChildName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    _ = store.addChild(name: name, birthDate: newChildBirth)
                    newChildName = ""
                }
                .disabled(newChildName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("The children")
        } footer: {
            Text("Each child gets their own book, their own timeline, their own ages — computed from the birthday you set here.")
        }
    }

    private func birthBinding(_ child: ChildProfile) -> Binding<Date> {
        Binding(
            get: { store.library.children.first { $0.id == child.id }?.birthDate ?? child.birthDate },
            set: { d in
                store.mutate { lib in
                    if let i = lib.children.firstIndex(where: { $0.id == child.id }) {
                        lib.children[i].birthDate = d
                    }
                }
            })
    }

    // MARK: Capture

    private var captureSection: some View {
        Section {
            Toggle("Pure contact — no touch-ups", isOn: settingBinding(\.pureContact))
            Toggle("Soft stamp sound", isOn: settingBinding(\.soundOn))
        } header: {
            Text("Making prints")
        } footer: {
            Text("Normally, if one little toe doesn't quite press while the others clearly do, the print is gently completed — and the print's page always tells you when that happened. Pure contact turns that off: prints stay exactly as pressed, gaps and all.")
        }
    }

    // MARK: Library

    private var librarySection: some View {
        Section {
            Toggle("Keep the book out of iCloud backup", isOn: settingBinding(\.excludeFromBackup))
        } header: {
            Text("The book on this phone")
        } footer: {
            Text("The book lives only on this phone. By default it rides along in your normal device backup (that's iOS, not us — nothing is sent anywhere by the app). Turn this on if you'd rather it never left the phone at all; just know a lost phone then means a lost book.")
        }
    }

    // MARK: Nightstand

    private var nightstandSection: some View {
        Section {
            Button {
                showNightstand = true
            } label: {
                HStack {
                    Label("Start Nightstand Walk", systemImage: "moon.stars.fill")
                        .foregroundColor(.inkPlum)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.inkFaint)
                }
            }
        } header: {
            Text("At night")
        } footer: {
            Text("Phone sideways on the charger, app open: her footprints walk quietly across a dark screen under a soft clock. It's the closest iOS allows to footprints on the locked screen — and the wallpaper in each print's page gives you her trail on the Lock Screen itself, as a picture that's always there.")
        }
    }

    // MARK: Privacy + about

    private var privacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Data Not Collected", systemImage: "lock.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundColor(.inkSoft)
                Text("Little Imprints has no account, no sign-in, and no server. It never uses the camera — a print is made from touch alone. There are no analytics, no ads, and no trackers of any kind. The only way anything leaves this phone is when you share it yourself.")
                    .font(.footnote)
                    .foregroundColor(.inkSoft)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Privacy, plainly")
        }
    }

    private var aboutSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Little Imprints")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.inkSoft)
                Text("Made to keep small prints at their true size. Version 1.0.")
                    .font(.footnote)
                    .foregroundColor(.inkFaint)
            }
            .padding(.vertical, 4)
        }
    }

    private func settingBinding(_ keyPath: WritableKeyPath<AppSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { store.library.settings[keyPath: keyPath] },
            set: { v in store.mutate { $0.settings[keyPath: keyPath] = v } })
    }
}
