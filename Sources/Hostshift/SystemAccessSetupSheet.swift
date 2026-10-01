import SwiftUI

struct SystemAccessSetupSheet: View {
    let access: SystemAccess

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SystemAccessView(access: access)
            HStack {
                Spacer()
                Button("Quit Hostshift") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
                    .disabled(access.isUpdating)
            }
            .padding([.horizontal, .bottom])
        }
        .padding(8)
        .frame(width: 440)
    }
}
