import AppKit
import SwiftUI

struct CommandLineSettingsView: View {
    @State private var command: [CommandLineLink] = []
    @State private var alias: [CommandLineLink] = []
    private let executable = Bundle.main.executableURL ?? Bundle.main.bundleURL.appending(path: "Contents/MacOS/Hostshift")

    private var installed: CommandLineLink? { command.first { $0.state == .thisApp } }
    /// Suggest the `hs` alias only when nothing else is using that name.
    private var suggestsAlias: Bool { alias.isEmpty }
    private var commands: String { CommandLineInstall.installCommands(executable: executable, includeAlias: suggestsAlias) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Command Line")
                .font(.headline)
            if let installed {
                Label("The hostshift command is installed at \(installed.path).", systemImage: "checkmark.circle")
            } else {
                ForEach(command, id: \.path) { link in
                    Label(link.state == .broken ? "\(link.path) is a broken link." : "\(link.path) runs a different copy of Hostshift or another program.",
                          systemImage: "exclamationmark.triangle")
                }
                Text("To install the hostshift command, run these commands in Terminal:")
                Text(commands)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Copy Commands") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(commands, forType: .string)
                    }
                    Button("Check Again", action: refresh)
                }
            }
            if !suggestsAlias, alias.allSatisfy({ $0.state != .thisApp }) {
                Text("Another program already uses the name hs, so the short alias isn’t suggested.")
                    .foregroundStyle(.secondary)
            }
            Link("Command-line reference", destination: URL(string: "https://github.com/dmallory42/hostshift/blob/main/docs/cli.md")!)
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .onAppear(perform: refresh)
    }

    private func refresh() {
        command = CommandLineInstall.links(named: "hostshift", executable: executable)
        alias = CommandLineInstall.links(named: "hs", executable: executable)
    }
}
