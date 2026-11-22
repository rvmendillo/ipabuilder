import Foundation
import SwiftUI
import UIKit
import ReyForgeCore
import Zsign

/// Builds a real, installable IPA on device: runtime template → project + branding → zsign → IPA.
@MainActor
final class BuildService: ObservableObject {
    enum Step: Int, CaseIterable, Identifiable {
        case prepare, assemble, icons, sign, package, done
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .prepare: return "Preparing runtime"
            case .assemble: return "Assembling app"
            case .icons: return "Rendering icon"
            case .sign: return "Signing"
            case .package: return "Packaging IPA"
            case .done: return "Ready"
            }
        }
    }

    struct Result: Equatable {
        let ipa: URL
        let bundleID: String
        let name: String
        let version: String
        let signed: Bool
        let size: Int64
        let seconds: Double
    }

    @Published private(set) var step: Step?
    @Published private(set) var log: [String] = []
    @Published private(set) var result: Result?
    @Published var error: String?
    @Published private(set) var isBuilding = false

    private func note(_ s: String) { log.append(s) }

    /// Locates (and unpacks once) the precompiled runtime app embedded in ReyForge.
    nonisolated static func runtimeTemplate() throws -> URL {
        let fm = FileManager.default
        guard let zip = Bundle.main.url(forResource: "RuntimeTemplate", withExtension: "zip") else {
            throw VaultError("This ReyForge build doesn't include the app runtime (RuntimeTemplate.zip).")
        }
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let size = (try? fm.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.int64Value ?? 0
        let dest = Paths.work.appendingPathComponent("runtime-\(build)-\(size)", isDirectory: true)
        let app = dest.appendingPathComponent("ReyForgeRuntime.app")
        if fm.fileExists(atPath: app.appendingPathComponent("Info.plist").path) { return app }
        try? fm.removeItem(at: dest)
        try ZipReader(url: zip).extractAll(to: dest)
        if fm.fileExists(atPath: app.path) { return app }
        // Fallback: find the .app anywhere in the archive.
        let found = fm.enumerator(at: dest, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL }.first { $0.pathExtension == "app" }
        guard let f = found else { throw VaultError("The runtime template is damaged.") }
        return f
    }

    /// Signs an .app folder with zsign (must not run on the main thread).
    nonisolated static func sign(app: URL, identity: SigningIdentity, workDir: URL) throws {
        let fm = FileManager.default
        let previous = fm.currentDirectoryPath
        // zsign keeps a small cache in the working directory.
        fm.changeCurrentDirectoryPath(workDir.path)
        defer { fm.changeCurrentDirectoryPath(previous) }
        var callbackOK = false
        let ok = Zsign.sign(appPath: app.path, provisionPath: identity.profileURL.path, p12Path: identity.p12URL.path,
                            p12Password: identity.password, entitlementsPath: "", customIdentifier: "", customName: "",
                            customVersion: "", adhoc: false, removeProvision: false) { success in callbackOK = success }
        guard ok && callbackOK else {
            throw VaultError("Signing failed. Check that the certificate password is right and that the profile matches the certificate.")
        }
    }

    /// Full pipeline. `identity == nil` produces an unsigned IPA for external signers.
    func build(project: Project, assets: [String: Data], identity: SigningIdentity?, includeWidget: Bool) async {
        guard !isBuilding else { return }
        isBuilding = true
        defer { isBuilding = false }
        error = nil
        result = nil
        log = []
        let started = Date()
        var project = project

        // Signing checks up front.
        var widget = includeWidget && project.widget.enabled
        if let id = identity, let profile = SigningVault.shared.profile(for: id) {
            if !profile.allows(bundleID: project.bundleID) && !profile.isWildcard {
                note("Bundle ID changed to \(profile.bundleIDPattern) to match your profile.")
                project.bundleID = profile.bundleIDPattern
            }
            if widget && !profile.allowsExtension(of: project.bundleID) {
                note("Widget left out: your profile doesn't cover \(project.bundleID).widget.")
                widget = false
            }
            if profile.isExpired { error = "Your provisioning profile expired. Import a new one in Signing."; return }
        }

        do {
            step = .prepare
            let template = try await Task.detached(priority: .userInitiated) { try BuildService.runtimeTemplate() }.value
            note("Runtime: \(template.lastPathComponent)")

            step = .icons
            var iconImage: UIImage?
            if project.brand.icon.kind == .image, let asset = project.brand.icon.imageAsset, let d = assets[asset] { iconImage = UIImage(data: d) }
            let icons = AppIconView.renderPNGs(icon: project.brand.icon, theme: project.theme, assetImage: iconImage)
            note("Rendered \(icons.count) icon sizes")

            step = .assemble
            let options = try AssemblyOptions(project: project, icons: icons, assets: assets, includeWidget: widget)
            let work = Paths.scratch("build")
            let app = try await Task.detached(priority: .userInitiated) {
                try AppAssembler.assemble(templateApp: template, workDir: work, options: options)
            }.value
            note("Assembled \(app.lastPathComponent) (\(options.bundleID))")

            if let identity = identity {
                step = .sign
                try await Task.detached(priority: .userInitiated) { try BuildService.sign(app: app, identity: identity, workDir: work) }.value
                note("Signed with \(identity.certificateName)")
            }

            step = .package
            let name = AppAssembler.safeAppName(project.brand.displayName.isEmpty ? project.name : project.brand.displayName)
            let ipa = Paths.builds.appendingPathComponent("\(name)-\(project.version)\(identity == nil ? "-unsigned" : "").ipa")
            try await Task.detached(priority: .userInitiated) { try AppAssembler.packageIPA(workDir: work, to: ipa) }.value
            let info = try AppAssembler.inspect(ipa: ipa)
            try? FileManager.default.removeItem(at: work)
            let size = (try? FileManager.default.attributesOfItem(atPath: ipa.path)[.size] as? NSNumber)?.int64Value ?? 0
            step = .done
            result = Result(ipa: ipa, bundleID: info.bundleID, name: info.displayName, version: info.version, signed: identity != nil,
                            size: size, seconds: Date().timeIntervalSince(started))
            note("Built \(ipa.lastPathComponent) — \(size.byteString)")
            Haptics.success()
        } catch {
            self.error = error.localizedDescription
            note("Failed: \(error.localizedDescription)")
            step = nil
        }
    }

    func reset() {
        step = nil; result = nil; error = nil; log = []
    }
}
