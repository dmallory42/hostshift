import SwiftUI
import HostsCore

struct ProfileRenameSheet: View {
    let profile: Profile
    let store: ProfileStore
    @State private var name: String
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(profile: Profile, store: ProfileStore) {
        self.profile = profile
        self.store = store
        _name = State(initialValue: profile.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Profile").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    store.rename(id: profile.id, name: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onAppear { nameFocused = true }
    }
}
