import SwiftUI

@main
struct HostshiftApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @State private var store = ProfileStore()
    @State private var updater = UpdateChecker()

    init() {
        // AppKit controls punctuation and capitalization separately from
        // NSTextView's text replacement setting. Keep input literal in Hostshift.
        UserDefaults.standard.set(false, forKey: "NSAutomaticPeriodSubstitutionEnabled")
        UserDefaults.standard.set(false, forKey: "NSAutomaticCapitalizationEnabled")
    }

    var body: some Scene {
        Window("Hostshift", id: "main") {
            ContentView(store: store)
                .onAppear {
                    appDelegate.store = store
                    updater.canPresent = { !store.isBusy && !store.showSystemAccessSetup }
                }
                .task {
                    while !Task.isCancelled {
                        await updater.checkAutomatically()
                        do { try await Task.sleep(for: .seconds(3600)) } catch { return }
                    }
                }
        }
        .defaultSize(width: 940, height: 620)
        .commands {
            ProfileCommands(store: store)
            ProfileSaveCommands(store: store)
            CommandGroup(after: .appInfo) {
                Button(updater.isChecking ? "Checking for Updates…" : "Check for Updates…") {
                    Task { await updater.check() }
                }
                .disabled(updater.isChecking || store.isBusy)
            }
        }
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            QuickSwitchMenu(store: store)
        } label: {
            Image(systemName: "arrow.triangle.swap")
                .accessibilityLabel("Hostshift")
        }
        .menuBarExtraStyle(.menu)
        Settings {
            AppSettingsView(store: store, updater: updater)
        }
    }
}
