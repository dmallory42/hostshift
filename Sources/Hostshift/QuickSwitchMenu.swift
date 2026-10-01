import SwiftUI
import HostsCore

struct QuickSwitchMenu: View {
    let store: ProfileStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(menuStatus)
        if store.systemContent == nil {
            Text("System file unavailable")
        } else if store.activeID == nil {
            Text("System file differs from saved profiles")
        }
        if !store.systemAccess.isReady {
            Button("Enable System Access…", action: showMainWindow)
        }
        if store.hasUnsavedChanges {
            Button("Review Unsaved Changes…", action: showMainWindow)
        }
        if store.errorMessage != nil {
            Button("Review Error…", action: showMainWindow)
        }
        Divider()
        if store.profiles.isEmpty {
            Text("No saved profiles")
        } else {
            Section("Switch Profile") {
                ForEach(store.profiles) { profile in
                    Button {
                        switchProfile(profile.id)
                    } label: {
                        if store.activeID == profile.id {
                            Text("✓ \(profile.displayName) (Active)")
                        } else {
                            Text(profile.displayName)
                        }
                    }
                    .disabled(!store.canApply(profile))
                }
            }
        }
        Divider()
        Button("Open Hostshift…", action: showMainWindow)
            .keyboardShortcut("o")
        SettingsLink()
        Divider()
        Button("Quit Hostshift") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
            .disabled(store.isBusy)
    }

    private var menuStatus: String {
        if store.isApplying { return "Activating profile…" }
        if let active = store.activeProfile { return "Active: \(active.displayName)" }
        return "Hostshift"
    }

    private func switchProfile(_ id: UUID) {
        Task {
            await store.apply(id: id)
            if store.errorMessage != nil { showMainWindow() }
        }
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
