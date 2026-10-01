import SwiftUI

struct UpdateSettingsView: View {
    @Bindable var updater: UpdateChecker
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
                .disabled(!updater.isConfigured)
            Button(updater.isChecking ? "Checking for Updates…" : "Check for Updates…") {
                Task { await updater.check() }
            }
            .disabled(updater.isChecking)
            if !updater.isConfigured {
                Text("Updates aren’t available for this build.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}
