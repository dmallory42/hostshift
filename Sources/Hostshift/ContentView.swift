import SwiftUI
import HostsCore

struct ContentView: View {
    @Bindable var store: ProfileStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            // A full-window panel rather than a sheet: macOS refuses to quit an app while a sheet is open.
            if store.showSystemAccessSetup {
                SystemAccessSetupSheet(access: store.systemAccess)
                    .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView {
                    ProfileSidebar(store: store)
                    .navigationSplitViewColumnWidth(min: 190, ideal: 230)
                    .safeAreaInset(edge: .bottom) {
                        SystemHostsStatus(store: store)
                    }
                } detail: {
                    if let profile = store.selected {
                        ProfileEditor(profile: profile, store: store).id(profile.id)
                    } else {
                        ContentUnavailableView("Choose a Profile", systemImage: "arrow.triangle.swap", description: Text("Save your hosts configurations and switch between them."))
                    }
                }
                .navigationTitle("Hostshift")
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("New Profile", systemImage: "plus") { store.add() }
                            .labelStyle(.titleAndIcon)
                            .help("Create a hosts profile (⌘N)")
                            .disabled(store.library == nil)
                        Button("Save") { store.saveSelected() }
                            .help("Save the selected profile (⌘S)")
                            .disabled(!store.isUnsaved(id: store.selection))
                        Button {
                            Task { await store.applySelected() }
                        } label: {
                            Text(store.isApplying ? "Activating…" : "Activate")
                        }
                        .help(store.isUnsaved(id: store.selection) ? "Save and activate the selected profile (⌘Return)" : "Activate the selected profile to /etc/hosts (⌘Return)")
                        .keyboardShortcut(.return, modifiers: [.command])
                        .disabled(store.selected.map { !store.canApply($0) } ?? true)
                    }
                }
                .disabled(store.isApplying || !store.systemAccess.isReady)
            }
        }
        .overlay { if store.isApplying { ProgressView("Activating hosts profile…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)) } }
        .alert("Hostshift", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .sheet(item: $store.profileToRename) { profile in
            ProfileRenameSheet(profile: profile, store: store)
        }
        .confirmationDialog("Delete “\(store.profileToDelete?.name ?? "")”?", isPresented: $store.showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Profile", role: .destructive) {
                if let id = store.profileToDelete?.id { store.delete(id: id) }
                store.profileToDelete = nil
            }
            Button("Cancel", role: .cancel) { store.profileToDelete = nil }
        } message: {
            Text("This permanently deletes the profile and any unsaved changes. This cannot be undone.")
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { store.refresh() } }
        .frame(minWidth: 720, minHeight: 460)
    }
}
