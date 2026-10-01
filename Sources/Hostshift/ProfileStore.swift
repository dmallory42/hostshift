import SwiftUI
import HostsCore

@MainActor @Observable
final class ProfileStore {
    let systemAccess = SystemAccess()
    var library: ProfileLibrary?
    var selection: UUID?
    var showSystemAccessSetup = false
    var profileToRename: Profile?
    var profileToDelete: Profile?
    var showDeleteConfirmation = false
    var systemContent: String?
    var errorMessage: String?
    var isApplying = false
    private var drafts: [Profile] = []
    var hasUnsavedChanges: Bool { !drafts.isEmpty }
    var status = "Profiles are saved on this Mac."
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    private let installer = HostsInstaller()
    private let libraryURL: URL

    var profiles: [Profile] {
        let saved = library?.profiles ?? []
        return saved.map { profile in drafts.first { $0.id == profile.id } ?? profile } +
            drafts.filter { draft in !saved.contains { $0.id == draft.id } }
    }

    func isUnsaved(id: UUID?) -> Bool { drafts.contains { $0.id == id } }

    var selected: Profile? { profiles.first { $0.id == selection } }
    var activeID: UUID? { systemContent.flatMap { library?.activeID(matching: $0) } }

    init(libraryURL: URL = URL.applicationSupportDirectory.appending(path: "Hostshift/profiles.json")) {
        self.libraryURL = libraryURL
        do {
            let current = try String(contentsOfFile: "/etc/hosts", encoding: .utf8)
            systemContent = current
            if FileManager.default.fileExists(atPath: libraryURL.path) {
                library = try ProfileLibrary.load(from: libraryURL)
            } else {
                let initial = ProfileLibrary(original: current)
                try initial.save(to: libraryURL)
                library = initial
            }
            selection = activeID ?? profiles.first?.id
        } catch { errorMessage = "Could not open your profiles: \(error.localizedDescription)" }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self else { return }
                if !self.isApplying && !self.systemAccess.isUpdating { self.refresh() }
            }
        }
    }

    deinit { monitorTask?.cancel() }

    func canApply(_ profile: Profile) -> Bool {
        systemAccess.isReady && !isApplying && systemContent != nil &&
            (profile.id != activeID || isUnsaved(id: profile.id)) && HostsValidator.issues(in: profile.content).isEmpty
    }

    func refresh() {
        systemAccess.refresh()
        do { systemContent = try String(contentsOfFile: "/etc/hosts", encoding: .utf8) }
        catch { systemContent = nil; errorMessage = error.localizedDescription }
    }

    @discardableResult
    private func commit(_ updated: ProfileLibrary) -> Bool {
        do {
            try updated.save(to: libraryURL)
            library = updated
            return true
        } catch {
            status = "Changes are not saved. Check disk access and try saving again."
            errorMessage = "Could not save your profiles: \(error.localizedDescription)"
            return false
        }
    }

    func stage(_ profile: Profile) {
        guard !profile.isOriginal, profiles.first(where: { $0.id == profile.id })?.isOriginal == false else { return }
        if library?.profiles.first(where: { $0.id == profile.id }) == profile {
            drafts.removeAll { $0.id == profile.id }
        } else if let index = drafts.firstIndex(where: { $0.id == profile.id }) {
            drafts[index] = profile
        } else {
            drafts.append(profile)
        }
    }

    @discardableResult
    func saveSelected() -> Bool {
        guard let selected else { return false }
        return save(id: selected.id)
    }

    @discardableResult
    func save(id: UUID) -> Bool {
        guard let draft = drafts.first(where: { $0.id == id }), var updated = library else { return true }
        if let index = updated.profiles.firstIndex(where: { $0.id == id }) {
            updated.profiles[index] = draft
        } else {
            updated.profiles.append(draft)
        }
        guard commit(updated) else { return false }
        drafts.removeAll { $0.id == id }
        status = "Saved on this Mac. Activate to update /etc/hosts."
        return true
    }

    @discardableResult
    func saveAll() -> Bool {
        guard var updated = library else { return false }
        updated.profiles = profiles
        guard commit(updated) else { return false }
        drafts.removeAll()
        status = "Saved on this Mac. Activate to update /etc/hosts."
        return true
    }

    func add(name: String = "New Profile", content: String? = nil) {
        guard library != nil else { return }
        let profile = Profile(name: name, content: content ?? profiles.first(where: \.isOriginal)?.content ?? "")
        drafts.append(profile)
        selection = profile.id
    }

    func duplicate(id: UUID? = nil) {
        guard let profile = profiles.first(where: { $0.id == (id ?? selection) }) else { return }
        add(name: "\(profile.name) Copy", content: profile.content)
    }

    func requestRename(id: UUID?) {
        guard let profile = profiles.first(where: { $0.id == id }), !profile.isOriginal else { return }
        profileToRename = profile
    }

    func rename(id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, var profile = profiles.first(where: { $0.id == id }), !profile.isOriginal else { return }
        profile.name = name
        stage(profile)
    }

    func canDelete(id: UUID?) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else { return false }
        return !isApplying && !profile.isOriginal && systemContent != nil && profile.id != activeID
    }

    func requestDelete(id: UUID?) {
        refresh()
        guard canDelete(id: id), let profile = profiles.first(where: { $0.id == id }) else { return }
        profileToDelete = profile
        showDeleteConfirmation = true
    }

    func delete(id: UUID) {
        refresh()
        guard canDelete(id: id), var updated = library else { return }
        updated.profiles.removeAll { $0.id == id }
        guard commit(updated) else { return }
        drafts.removeAll { $0.id == id }
        if selection == id { selection = profiles.first?.id }
    }

    func captureCurrentHosts() {
        refresh()
        if let content = systemContent { add(name: "Current Hosts", content: content) }
    }

    func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import Hosts File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 96_000 else { throw NSError(domain: "Hostshift", code: 1, userInfo: [NSLocalizedDescriptionKey: "Keep profiles under 96 KB."]) }
            add(name: url.deletingPathExtension().lastPathComponent, content: try String(contentsOf: url, encoding: .utf8))
        } catch { errorMessage = error.localizedDescription }
    }

    func exportProfile() {
        guard let selected else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(selected.name).hosts"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try selected.content.write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = error.localizedDescription }
    }

    func applySelected() async {
        guard let selection else { return }
        await apply(id: selection)
    }

    func apply(id: UUID) async {
        guard !isApplying else { return }
        refresh()
        guard systemAccess.isReady,
              let selected = profiles.first(where: { $0.id == id }), let expected = systemContent else { return }
        errorMessage = nil
        let issues = HostsValidator.issues(in: selected.content)
        guard issues.isEmpty else { errorMessage = issues.joined(separator: "\n"); return }
        if library?.hasExternalChanges(in: expected) == true {
            switch Self.askAboutExternalChanges(selected) {
            case .cancel: return
            case .replace: break
            case .saveAsProfile: guard saveExternalChanges(expected) else { return }
            }
        }
        guard save(id: id) else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            status = try await installer.apply(content: selected.content, expected: expected)
            refresh()
            guard systemContent == selected.content else {
                errorMessage = "The hosts file no longer matches the profile. Another app may have changed it."
                return
            }
            if var updated = library {
                updated.preferredActiveID = selected.id
                updated.lastActivatedDigest = HostsInstallScript.digest(selected.content)
                commit(updated)
            }
        } catch {
            refresh()
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveExternalChanges(_ content: String) -> Bool {
        guard var updated = library else { return false }
        let names = Set(profiles.map(\.name))
        var name = "Copy of /etc/hosts"
        var number = 2
        while names.contains(name) {
            name = "Copy of /etc/hosts (\(number))"
            number += 1
        }
        updated.profiles.append(Profile(name: name, content: content))
        return commit(updated)
    }

    private static func askAboutExternalChanges(_ profile: Profile) -> ExternalChangeChoice {
        let alert = NSAlert()
        alert.messageText = "/etc/hosts has changed outside Hostshift"
        alert.informativeText = "Another app or a manual edit changed your hosts file. Activating “\(profile.name.isEmpty ? "Untitled" : profile.name)” will replace those changes."
        alert.addButton(withTitle: "Save as Profile")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[2].keyEquivalent = "\u{1b}"
        NSApplication.shared.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .saveAsProfile
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }
}

enum ExternalChangeChoice {
    case saveAsProfile, replace, cancel
}
