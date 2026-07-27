import Foundation

/// Checks GitHub Releases for a newer version than the one currently running —
/// no auto-download, no auto-install, just a link to the release page. Runs as
/// a side effect of normal use (app launch, panel show), throttled to once a
/// day via AppPreferences.lastUpdateCheckAt, same "no background polling"
/// philosophy as the Reminders/iCloud sync engines.
@MainActor
final class UpdateChecker: ObservableObject {
    struct AvailableUpdate: Equatable {
        let version: String
        let url: URL
    }

    @Published private(set) var availableUpdate: AvailableUpdate?

    private let preferences: AppPreferences
    private let repo = "jtoeman/squirreltrap"
    private let checkInterval: TimeInterval = 24 * 60 * 60

    init(preferences: AppPreferences) {
        self.preferences = preferences
    }

    /// Safe to call from every launch and every panel show — only actually
    /// hits the network if it's been at least a day since the last check.
    func checkIfDue() async {
        if let last = preferences.lastUpdateCheckAt, Date().timeIntervalSince(last) < checkInterval {
            return
        }
        await check()
    }

    func check() async {
        preferences.lastUpdateCheckAt = Date()
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                  Self.isNewer(latestVersion, than: currentVersion),
                  let releaseURL = URL(string: release.htmlURL) else {
                availableUpdate = nil
                return
            }
            availableUpdate = AvailableUpdate(version: latestVersion, url: releaseURL)
        } catch {
            debugLog("Squirrel Trap DEBUG: [UpdateChecker] check failed: \(error)\n")
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// Numeric, dot-separated comparison (e.g. "1.10.0" > "1.9.0") — a plain
    /// string comparison would get that case wrong.
    private static func isNewer(_ a: String, than b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let x = i < aParts.count ? aParts[i] : 0
            let y = i < bParts.count ? bParts[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
