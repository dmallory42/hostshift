import SwiftUI
import HostsCore

struct ProfileEditor: View {
    @State private var draft: Profile
    @State private var lineSelection: EditorLineSelection?
    let store: ProfileStore

    init(profile: Profile, store: ProfileStore) {
        _draft = State(initialValue: profile)
        self.store = store
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if draft.isOriginal {
                    Text(draft.name).font(.title2.bold())
                    Label("Read-only", systemImage: "lock")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .help("Your hosts file when Hostshift first opened")
                    Spacer()
                } else {
                    TextField("Profile name", text: $draft.name)
                        .font(.title2.bold())
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Profile name")
                }
                Button("Duplicate") { store.duplicate(id: draft.id) }
                    .help(draft.isOriginal ? "Create an editable copy of Original" : "Create a copy of this profile")
                if store.activeID == draft.id {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }
            .padding()
            Divider()
            HostsTextEditor(text: $draft.content, isEditable: !draft.isOriginal, lineSelection: lineSelection)
                .accessibilityLabel("Hosts file contents")
            Divider()
            EditorStatusBar(isUnsaved: store.isUnsaved(id: draft.id), issues: HostsValidator.diagnostics(in: draft.content)) { line in
                lineSelection = EditorLineSelection(line: line)
            }
        }
        .background(.background)
        .onChange(of: store.selected?.name) { _, name in
            if let name, store.selection == draft.id { draft.name = name }
        }
        .onChange(of: draft) { _, value in store.stage(value) }
    }
}
