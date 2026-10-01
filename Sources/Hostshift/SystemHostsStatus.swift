import SwiftUI

struct SystemHostsStatus: View {
    let store: ProfileStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let active = store.activeProfile {
                Label("Active: \(active.displayName)", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
                if store.selection != active.id {
                    Button("Show Active Profile") { store.selection = active.id }
                        .buttonStyle(.link)
                }
            } else if store.systemContent != nil {
                Label("System hosts differ", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
                    .help("The system hosts file doesn’t match any saved profile.")
                Button("Capture as Profile") { store.captureCurrentHosts() }
                    .buttonStyle(.link)
                    .help("Create a new profile from the current /etc/hosts file")
            } else {
                Label("System hosts unavailable", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                Button("Try Again") { store.refresh() }
                    .buttonStyle(.link)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}
