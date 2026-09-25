import SwiftUI
import ServiceManagement
import HostsCore

@MainActor @Observable
final class SystemAccess {
    private let service = SMAppService.daemon(plistName: HelperIdentity.plistName)
    private let localSetup = LocalSetup()
    private var localRegistration: LocalRegistration?
    private var helperURL: URL?
    var status: SMAppService.Status = .notRegistered
    var isLocalBuild = false
    var errorMessage: String?
    var isUpdating = false
    var requiresRestart = false

    var isReady: Bool { status == .enabled && !isUpdating }
    var needsApproval: Bool { status == .requiresApproval }

    init() {
        isLocalBuild = (try? HelperIdentity.peerRequirement(identifier: HelperIdentity.serviceName)) == nil
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
        if isLocalBuild {
            if let localRegistration {
                requiresRestart = (try? CodeIdentity.requirement(at: Bundle.main.bundleURL)) != localRegistration.clientRequirement
                if requiresRestart {
                    status = .notRegistered
                    return
                }
            }
            guard let localRegistration, let installed = try? LocalRegistration.load(), installed == localRegistration else {
                status = .notRegistered
                return
            }
            status = Self.localServiceIsLoaded() ? .enabled : .notRegistered
        } else { status = service.status }
    }

    func enable() async {
        refresh()
        guard !requiresRestart else { return }
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
            refresh()
            if needsApproval { SMAppService.openSystemSettingsLoginItems(); return }
            do { try service.register() }
            catch {
                refresh()
                if !needsApproval { errorMessage = error.localizedDescription }
            }
            refresh()
            if needsApproval { SMAppService.openSystemSettingsLoginItems() }
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

    private static func localServiceIsLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "system/" + HelperIdentity.serviceName]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { return false }
    }
}
