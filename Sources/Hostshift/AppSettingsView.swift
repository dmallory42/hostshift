import SwiftUI

struct AppSettingsView: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    let store: ProfileStore
    let updater: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle("Show Hostshift in the menu bar", isOn: $showMenuBarExtra)
                .padding()
            Divider()
            UpdateSettingsView(updater: updater)
            Divider()
            SystemAccessView(access: store.systemAccess)
        }
        .frame(width: 440)
        .disabled(store.isApplying)
    }
}
