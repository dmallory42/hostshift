import SwiftUI

struct SystemAccessView: View {
    @Bindable var access: SystemAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label(access.requiresRestart ? "Restart Hostshift" : access.isReady ? "System access is enabled" : "Enable host switching", systemImage: access.isReady ? "checkmark.shield" : "lock.shield")
                    .font(.headline)
                Text(access.requiresRestart ? "Hostshift was updated while it was open. Quit and reopen the app, then enable system access for the new build." : access.isReady ? "You can switch profiles without entering your password again." : "Hostshift needs permission to update your Mac’s hosts file. Approve access once to switch profiles without a password each time.")
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                if access.isUpdating {
                    ProgressView("Waiting for macOS authorisation…")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else if access.isReady {
                    Button("Disable System Access") { Task { await access.disable() } }
                } else if !access.requiresRestart {
                    Button(access.needsApproval ? "Approve in System Settings…" : "Enable System Access…") {
                        Task { await access.enable() }
                    }
                    .buttonStyle(.borderedProminent)
                    if access.needsApproval {
                        Text("Allow Hostshift under Login Items & Extensions in System Settings.").font(.callout)
                    } else if access.isLocalBuild {
                        Text("macOS will ask for administrator approval. This is needed for setup and app updates.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            if let error = access.errorMessage { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(access.isUpdating)
    }
}
