import Foundation
import SwiftUI
import ReyForgeCore

/// Updates ReyForge itself from GitHub releases built by the repository's workflow:
/// downloads the IPA, re-signs it on device with your certificate and installs it over this copy.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    @Published private(set) var releases: [GitHubRelease] = []
    @Published private(set) var isChecking = false
    @Published private(set) var isInstalling = false
    @Published var status = ""
    @Published var error: String?
    @Published private(set) var lastChecked: Date?

    var currentVersion: String { RF.appVersion }
    var currentBuild: Int { Int(RF.appBuild) ?? 0 }

    /// Releases with an installable IPA, newest first.
    var installable: [GitHubRelease] { releases.filter { $0.ipaAsset(preferLite: true) != nil } }
    var latest: GitHubRelease? { installable.first }

    static func build(of release: GitHubRelease) -> Int? {
        let text = (release.name ?? "") + " " + release.tag_name
        guard let open = text.lastIndex(of: "("), let close = text.lastIndex(of: ")"), open < close else { return nil }
        return Int(text[text.index(after: open)..<close])
    }

    static func version(of release: GitHubRelease) -> String {
        if release.tag_name.hasPrefix("v") { return release.version }
        // Nightly titles look like "ReyForge 3.0 nightly (42)".
        let words = (release.name ?? "").split(separator: " ")
        return words.first { $0.first?.isNumber == true }.map(String.init) ?? release.version
    }

    func isNewer(_ release: GitHubRelease) -> Bool {
        let v = Self.version(of: release)
        if SemVer.isNewer(v, than: currentVersion) { return true }
        if SemVer.compare(v, currentVersion) == 0, let b = Self.build(of: release) { return b > currentBuild }
        return false
    }

    var updateAvailable: Bool { latest.map(isNewer) ?? false }

    func check(settings: AppSettings) async {
        isChecking = true
        error = nil
        defer { isChecking = false }
        let client = GitHubClient(owner: settings.updateOwner, repo: settings.updateRepo, token: settings.githubToken.isEmpty ? nil : settings.githubToken)
        do {
            releases = try await client.releases(perPage: 15)
            lastChecked = Date()
            status = updateAvailable ? "Update available" : "ReyForge is up to date"
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Download → re-sign with your certificate (keeping this app's bundle id) → install.
    func install(_ release: GitHubRelease, identity: SigningIdentity, settings: AppSettings) async {
        guard let asset = release.ipaAsset(preferLite: settings.preferLiteUpdates) else { error = "This release has no IPA."; return }
        isInstalling = true
        error = nil
        defer { isInstalling = false }
        let client = GitHubClient(owner: settings.updateOwner, repo: settings.updateRepo, token: settings.githubToken.isEmpty ? nil : settings.githubToken)
        let work = Paths.scratch("update")
        let downloaded = work.appendingPathComponent("download.ipa")
        do {
            status = "Downloading \(asset.name) (\(Int64(asset.size).byteString))…"
            try await client.download(asset: asset, to: downloaded)
            status = "Preparing…"
            let bundleID = Bundle.main.bundleIdentifier ?? "com.rvmendillo.reyforge"
            let app: URL = try await Task.detached(priority: .userInitiated) {
                try ZipReader(url: downloaded).extractAll(to: work)
                try? FileManager.default.removeItem(at: downloaded)
                let payload = work.appendingPathComponent("Payload")
                guard let app = try FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "app" }) else {
                    throw VaultError("The downloaded IPA has no app inside.")
                }
                // Keep this installation's identity so the update replaces it (and keeps your projects).
                try AppAssembler.rewriteIdentity(app: app, bundleID: bundleID, displayName: nil)
                return app
            }.value
            status = "Signing with \(identity.certificateName)…"
            try await Task.detached(priority: .userInitiated) { try BuildService.sign(app: app, identity: identity, workDir: work) }.value
            status = "Packaging…"
            let ipa = Paths.builds.appendingPathComponent("ReyForge-\(Self.version(of: release))-update.ipa")
            try await Task.detached(priority: .userInitiated) { try AppAssembler.packageIPA(workDir: work, to: ipa) }.value
            try? FileManager.default.removeItem(at: work)
            status = "Installing — confirm the prompt, then ReyForge restarts."
            try await DeviceInstaller.install(ipa: ipa, bundleID: bundleID, name: "ReyForge", version: Self.version(of: release))
        } catch {
            self.error = error.localizedDescription
            status = ""
        }
    }
}
