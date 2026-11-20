import SwiftUI
import HostsCore

@MainActor @Observable
final class ProfileStore {
    typealias Install = ProfileActivation.Install

    let systemAccess: SystemAccess
    var library: ProfileLibrary?
    var selection: UUID?
    var showSystemAccessSetup: Bool { !systemAccess.isReady }
    var profileToRename: Profile?
    var profileToDelete: Profile?
    var showDeleteConfirmation = false
    var systemContent: String?
    var errorMessage: String?
    var isApplying = false
    private var drafts: [Profile] = []
    var hasUnsavedChanges: Bool { !drafts.isEmpty }
    var isBusy: Bool { isApplying || systemAccess.isUpdating }
    @ObservationIgnored private var monitorTask: Task<Void, Never>?
    private let install: Install
    private let askAboutExternalChanges: @MainActor (Profile) -> ExternalChangeChoice
    private let libraryFile: ProfileLibraryFile
    private let hostsURL: URL
    /// The version of profiles.json last read or written here. A different stamp means the command-line tool changed it.
    @ObservationIgnored private var libraryStamp: ProfileLibraryFile.Stamp?

    var profiles: [Profile] {
        let saved = library?.profiles ?? []
        return saved.map { profile in drafts.first { $0.id == profile.id } ?? profile } +
            drafts.filter { draft in !saved.contains { $0.id == draft.id } }
    }

    func isUnsaved(id: UUID?) -> Bool { drafts.contains { $0.id == id } }

    var selected: Profile? { profiles.first { $0.id == selection } }
    var activeProfile: Profile? { library?.profiles.first { $0.id == activeID } }
    var activeID: UUID? { systemContent.flatMap { library?.activeID(matching: $0) } }

    /// The defaults are the real system. Checks substitute the hosts file, system access, helper call and prompt.
    init(libraryURL: URL = ProfileLibraryFile.standard.url,
         hostsURL: URL = URL(fileURLWithPath: "/etc/hosts"),
         systemAccess: SystemAccess = SystemAccess(),
         install: @escaping Install = { try await HostsInstaller().apply(content: $0, expected: $1) },
         askAboutExternalChanges: @escaping @MainActor (Profile) -> ExternalChangeChoice = ProfileStore.presentExternalChangesAlert) {
        libraryFile = ProfileLibraryFile(url: libraryURL)
        self.hostsURL = hostsURL
        self.systemAccess = systemAccess
        self.install = install
        self.askAboutExternalChanges = askAboutExternalChanges
        readSystemHosts(reportingRepeatedFailure: true)
        loadLibrary()
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self else { return }
                if !self.isBusy { await self.refreshFromMonitor() }
            }
        }
    }

    deinit { monitorTask?.cancel() }

    func canApply(_ profile: Profile) -> Bool {
        systemAccess.isReady && !isApplying && systemContent != nil &&
            (profile.id != activeID || isUnsaved(id: profile.id)) && HostsValidator.issues(in: profile.content).isEmpty
    }

    func refresh(reportingRepeatedFailure: Bool = false) {
        systemAccess.refresh()
        readSystemHosts(reportingRepeatedFailure: reportingRepeatedFailure)
        reloadLibraryIfChanged()
    }

    private func refreshFromMonitor() async {
        await systemAccess.refreshInBackground()
        if !isBusy {
            readSystemHosts()
            reloadLibraryIfChanged()
        }
    }

    /// Picks up changes another process saved, such as the command-line tool. Drafts are kept,
    /// except those that now match what is saved. A read failure keeps the library already loaded.
    private func reloadLibraryIfChanged() {
        guard library != nil, libraryFile.stamp() != libraryStamp,
              let snapshot = try? libraryFile.load() else { return }
        libraryStamp = snapshot.stamp
        if library != snapshot.library { library = snapshot.library }
        drafts.removeAll { snapshot.library.profiles.contains($0) }
        if let selection, !profiles.contains(where: { $0.id == selection }) {
            self.selection = activeID ?? profiles.first?.id
        }
    }

    /// The monitor polls every few seconds, so a read failure is reported when the file stops being readable, not on every poll.
    private func readSystemHosts(reportingRepeatedFailure: Bool = false) {
        let wasUnavailable = systemContent == nil
        do {
            let current = try String(contentsOf: hostsURL, encoding: .utf8)
            if systemContent != current { systemContent = current }
            if wasUnavailable && library == nil && !libraryFile.exists { loadLibrary() }
        } catch {
            guard !wasUnavailable || reportingRepeatedFailure else { return }
            systemContent = nil
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the saved library. On first launch it snapshots the hosts file as Original, once that file is readable.
    private func loadLibrary() {
        guard library == nil else { return }
        do {
            guard let snapshot = try libraryFile.loadOrCreate(original: systemContent) else { return }
            library = snapshot.library
            libraryStamp = snapshot.stamp
            selection = activeID ?? profiles.first?.id
        } catch { errorMessage = "Could not open your profiles: \(error.localizedDescription)" }
    }

    /// Applies one change to the latest saved library, so changes saved by the command-line tool are kept.
    @discardableResult
    private func commit(_ change: (inout ProfileLibrary) throws -> Void) -> Bool {
        do {
            let snapshot = try libraryFile.update(change)
            library = snapshot.library
            libraryStamp = snapshot.stamp
            return true
        } catch {
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
        guard let draft = drafts.first(where: { $0.id == id }), library != nil else { return true }
        guard commit({ try $0.upsert(draft) }) else { return false }
        drafts.removeAll { $0.id == id }
        return true
    }

    @discardableResult
    func saveAll() -> Bool {
        let pending = drafts
        guard library != nil, commit({ library in
            for draft in pending { try library.upsert(draft) }
        }) else { return false }
        drafts.removeAll()
        return true
    }

    func add(name: String = "New Profile", content: String? = nil) {
        guard library != nil else { return }
        let profile = Profile(name: ProfileLibrary.uniqueName(name, among: Set(profiles.map(\.name))), content: content ?? profiles.first(where: \.isOriginal)?.content ?? "")
        drafts.append(profile)
        selection = profile.id
    }

    func duplicate(id: UUID? = nil) {
        guard let profile = profiles.first(where: { $0.id == (id ?? selection) }) else { return }
        add(name: "Copy of \(profile.displayName)", content: profile.content)
    }

    func requestRename(id: UUID?) {
        guard let profile = profiles.first(where: { $0.id == id }), !profile.isOriginal else { return }
        profileToRename = profile
    }

    func rename(id: UUID, name: String) {
        guard let name = ProfileLibrary.normalizedName(name), var profile = profiles.first(where: { $0.id == id }), !profile.isOriginal else { return }
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
        guard canDelete(id: id), let systemContent else { return }
        guard commit({ try $0.remove(id: id, systemContent: systemContent) }) else { return }
        drafts.removeAll { $0.id == id }
        if selection == id { selection = profiles.first?.id }
    }

    func captureCurrentHosts() {
        refresh()
        if let content = systemContent { add(name: ProfileLibrary.copyOfHostsName, content: content) }
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
        panel.nameFieldStringValue = selected.exportFileName
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
        guard systemAccess.isReady, let selected = profiles.first(where: { $0.id == id }), systemContent != nil else { return }
        errorMessage = nil
        isApplying = true
        defer { isApplying = false }
        let activation = ProfileActivation(library: libraryFile, hostsURL: hostsURL, install: install)
        let ask = askAboutExternalChanges
        do {
            if let warning = try await activation.run(selected, reservedNames: Set(drafts.map(\.name)),
                                                      resolveExternalChanges: { await ask($0) }) {
                errorMessage = warning
            }
        } catch .cancelled {
        } catch { errorMessage = error.localizedDescription }
        // The activation saved the profile, so its draft is dropped when the library reloads.
        refresh()
    }

    @discardableResult
    func saveExternalChanges(_ content: String) -> Bool {
        guard library != nil else { return false }
        let reserved = Set(drafts.map(\.name))
        return commit { _ = $0.add(name: ProfileLibrary.copyOfHostsName, content: content, reservedNames: reserved) }
    }

    static func presentExternalChangesAlert(_ profile: Profile) -> ExternalChangeChoice {
        let alert = NSAlert()
        alert.messageText = "/etc/hosts has changed outside Hostshift"
        alert.informativeText = "Another app or a manual edit changed your hosts file. Activating “\(profile.displayName)” will replace those changes."
        alert.addButton(withTitle: "Save as Profile")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .saveAsProfile
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }
}

extension Profile {
    var displayName: String { name.isEmpty ? "Untitled" : name }
    /// The save panel and Finder treat slashes and colons as path separators.
    var exportFileName: String { displayName.replacing("/", with: "-").replacing(":", with: "-") + ".hosts" }
}
