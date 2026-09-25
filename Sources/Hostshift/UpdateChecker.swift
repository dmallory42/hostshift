import SwiftUI
import HostsCore

@MainActor @Observable
final class UpdateChecker {
    @ObservationIgnored var canPresent: () -> Bool = { true }
    var isChecking = false
    var automaticallyChecks: Bool {
        didSet { UserDefaults.standard.set(automaticallyChecks, forKey: "automaticallyCheckForUpdates") }
    }
    private let repository: String?
    var isConfigured: Bool { repository != nil }

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "HostshiftUpdateRepository") as? String
        repository = configured.flatMap { AppRelease.validRepository($0) ? $0 : nil }
        automaticallyChecks = UserDefaults.standard.bool(forKey: "automaticallyCheckForUpdates")
    }

    func checkAutomatically() async {
        guard automaticallyChecks, isConfigured else { return }
        let last = UserDefaults.standard.object(forKey: "lastSuccessfulUpdateCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= 86_400 else { return }
        await check(manual: false)
    }

    func check(manual: Bool = true) async {
        guard !isChecking else { return }
        guard canPresent() else { return }
        guard let repository else {
            if manual { show(message: "Updates aren’t available for this build.", detail: "You can continue using this version of Hostshift.") }
            return
        }
        isChecking = true
        defer { isChecking = false }
        do {
            let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Hostshift", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard canPresent() else { return }
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if response.statusCode == 404 {
                if manual { show(message: "No release is available.", detail: "Hostshift couldn’t find a published release. Please try again later.") }
                return
            }
            guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            guard let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let newer = try release.isNewer(than: current, repository: repository)
            UserDefaults.standard.set(Date(), forKey: "lastSuccessfulUpdateCheck")
            if newer {
                let alert = NSAlert()
                alert.messageText = "Hostshift \(release.tag_name) is available"
                alert.informativeText = "You’re using version \(current). View the release notes and download the update on GitHub."
                alert.addButton(withTitle: "View Release")
                alert.addButton(withTitle: "Later")
                if manual { NSApplication.shared.activate(ignoringOtherApps: true) }
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.html_url) }
            } else if manual {
                show(message: "You’re up to date", detail: "Hostshift \(current) is the latest available version.")
            }
        } catch {
            if manual && canPresent() { show(message: "Couldn’t check for updates", detail: "Please try again later. \(error.localizedDescription)") }
        }
    }

    private func show(message: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
