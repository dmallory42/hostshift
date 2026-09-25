import SwiftUI
import HostsCore

struct EditorStatusBar: View {
    let isUnsaved: Bool
    let issues: [HostsDiagnostic]
    let selectLine: (Int) -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if isUnsaved {
                    Label("Unsaved changes", systemImage: "circle.fill")
                } else {
                    Text("Saved")
                }
                Spacer()
                if issues.isEmpty {
                    Label("Valid configuration", systemImage: "checkmark.circle")
                } else {
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Label("\(issues.count) \(issues.count == 1 ? "issue" : "issues")", systemImage: isExpanded ? "chevron.down" : "chevron.up")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(isExpanded ? "Hide" : "Show") \(issues.count) validation issues")
                    .help("Show validation issues and jump to their lines")
                }
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 10)
            if isExpanded && !issues.isEmpty {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            if let line = issue.line {
                                Button { selectLine(line) } label: {
                                    Label(issue.description, systemImage: "exclamationmark.triangle")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .multilineTextAlignment(.leading)
                                }
                                .buttonStyle(.link)
                                .help("Select line \(line) in the editor")
                            } else {
                                Label(issue.description, systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 140)
            }
        }
        .font(.callout)
        .onChange(of: issues.isEmpty) { _, empty in
            if empty { isExpanded = false }
        }
    }
}
