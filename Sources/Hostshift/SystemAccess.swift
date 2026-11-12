import SwiftUI
import ServiceManagement
import HostsCore

@MainActor @Observable
final class SystemAccess {
    private let service = SMAppService.daemon(plistName: HelperIdentity.plistName)
    private let localSetup = LocalSetup()
    private var localRegistration: LocalRegistration?
    private var helperURL: URL?
    private let fixedStatus: SMAppService.Status?
    @ObservationIgnored private var refreshCount = 0
    var status: SMAppService.Status = .notRegistered
    var isLocalBuild = false
    var errorMessage: String?
    var isUpdating = false
    var requiresRestart = false

    var isReady: Bool { status == .enabled && !isUpdating }
    var needsApproval: Bool { status == .requiresApproval }
    /// Apple-signed builds register their helper with SMAppService, which needs the app in /Applications.
    var needsApplicationsFolder: Bool { !isLocalBuild && !Self.isInApplicationsFolder(Bundle.main.bundleURL) }

    nonisolated static func isInApplicationsFolder(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix("/Applications/")
    }

    /// Checks pass a fixed status so they never query launchd or the installed helper.
    init(fixedStatus: SMAppService.Status? = nil) {
        self.fixedStatus = fixedStatus
        isLocalBuild = fixedStatus == nil && (try? HelperIdentity.peerRequirement(identifier: HelperIdentity.serviceName)) == nil
        if isLocalBuild {
            do {
                let helper = Bundle.main.bundleURL.appending(path: "Contents/MacOS/HostshiftHelper")
                helperURL = helper
                localRegistration = LocalRegistration(
                    clientRequirement: try CodeIdentity.ownRequirement(),
                    helperRequirement: try CodeIdentity.requirement(at: helper),
                    userID: getuid()
                )
            } catch { errorMessage = "Could not verify this app build: \(error.localizedDescription)" }
        }
        refresh()
    }

    func refresh() {
        refreshCount += 1
        if let fixedStatus {
            update(requiresRestart: false, status: fixedStatus)
        } else if isLocalBuild {
            let state = Self.localState(for: localRegistration, bundle: Bundle.main.bundleURL)
            update(requiresRestart: state.requiresRestart, status: state.status)
        } else {
            update(requiresRestart: false, status: service.status)
        }
    }

    /// The same refresh for the periodic monitor. A local build verifies its signature and asks launchctl, which is too slow to repeat on the main thread.
    func refreshInBackground() async {
        guard isLocalBuild else { refresh(); return }
        let count = refreshCount
        let registration = localRegistration
        let bundle = Bundle.main.bundleURL
        let state = await Task.detached { Self.localState(for: registration, bundle: bundle) }.value
        // A direct refresh or a setup run that happened meanwhile is newer than this result.
        guard count == refreshCount, !isUpdating else { return }
        update(requiresRestart: state.requiresRestart, status: state.status)
    }

    private func update(requiresRestart: Bool, status: SMAppService.Status) {
        if self.requiresRestart != requiresRestart { self.requiresRestart = requiresRestart }
        if self.status != status { self.status = status }
    }

    private nonisolated static func localState(for registration: LocalRegistration?, bundle: URL) -> (requiresRestart: Bool, status: SMAppService.Status) {
        guard let registration else { return (false, .notRegistered) }
        if (try? CodeIdentity.requirement(at: bundle)) != registration.clientRequirement { return (true, .notRegistered) }
        guard let installed = try? LocalRegistration.load(), installed == registration, localServiceIsLoaded() else {
            return (false, .notRegistered)
        }
        return (false, .enabled)
    }

    func enable() async {
        refresh()
        guard !requiresRestart, !needsApplicationsFolder else { return }
        errorMessage = nil
        isUpdating = true
        defer { isUpdating = false; refresh() }
        if isLocalBuild {
            guard let helperURL, let localRegistration else {
                errorMessage = "Rebuild Hostshift before enabling system access."
                return
            }
            do {
                let script = try LocalSetupScript.install(helperURL: helperURL, registration: localRegistration)
                try await localSetup.run(script)
            } catch { errorMessage = error.localizedDescription }
        } else {
            if needsApproval { SMAppService.openSystemSettingsLoginItems(); return }
            var failure: (any Error)?
            do { try service.register() } catch { failure = error }
            refresh()
            if needsApproval { SMAppService.openSystemSettingsLoginItems() }
            else if let failure { errorMessage = failure.localizedDescription }
        }
    }

    func disable() async {
        errorMessage = nil
        isUpdating = true
        defer { isUpdating = false; refresh() }
        do {
            if isLocalBuild { try await localSetup.run(LocalSetupScript.uninstall) }
            else { try await service.unregister() }
        } catch { errorMessage = error.localizedDescription }
    }

    private nonisolated static func localServiceIsLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/" + HelperIdentity.serviceName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }
}
