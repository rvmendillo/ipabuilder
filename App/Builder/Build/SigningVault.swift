import Foundation
import Security
import ReyForgeCore
import Zsign

struct VaultError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// A certificate (.p12) + provisioning profile pair used to sign apps on device.
struct SigningIdentity: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var createdAt: Date
    var certificateName: String
    var certificateExpiry: Date?
    var profileName: String
    var teamID: String
    var teamName: String
    var appIDPattern: String
    var profileExpiry: Date?
    var kind: String
    var deviceCount: Int

    var folder: URL { Paths.signing.appendingPathComponent(id, isDirectory: true) }
    var p12URL: URL { folder.appendingPathComponent("cert.p12") }
    var profileURL: URL { folder.appendingPathComponent("profile.mobileprovision") }
    var password: String { SecretStore.get("sign.\(id)") ?? "" }
    var isWildcard: Bool { appIDPattern.hasSuffix("*") }
    var isExpired: Bool { (profileExpiry ?? .distantFuture) < Date() || (certificateExpiry ?? .distantFuture) < Date() }
}

@MainActor
final class SigningVault: ObservableObject {
    static let shared = SigningVault()
    @Published private(set) var identities: [SigningIdentity] = []
    @Published var revocation: [String: String] = [:]

    init() { reload() }

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Paths.signing, includingPropertiesForKeys: nil)) ?? []
        identities = dirs.compactMap { dir in
            guard let d = try? Data(contentsOf: dir.appendingPathComponent("identity.json")) else { return nil }
            return try? JSONDecoder().decode(SigningIdentity.self, from: d)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func identity(_ id: String) -> SigningIdentity? { identities.first { $0.id == id } }

    func profile(for identity: SigningIdentity) -> ProvisioningProfile? {
        guard let d = try? Data(contentsOf: identity.profileURL) else { return nil }
        return try? ProvisioningProfile.parse(d)
    }

    /// Validates the password and reads the certificate. Unknown PKCS#12 encodings are accepted (zsign reads them).
    nonisolated static func inspectP12(_ data: Data, password: String) throws -> (name: String, expiry: Date?) {
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, [kSecImportExportPassphrase as String: password] as CFDictionary, &items)
        if status == errSecAuthFailed { throw VaultError("The certificate password is incorrect.") }
        guard status == errSecSuccess, let list = items as? [[String: Any]], let first = list.first,
              let raw = first[kSecImportItemIdentity as String], CFGetTypeID(raw as CFTypeRef) == SecIdentityGetTypeID() else {
            return ("Signing certificate", nil)
        }
        let identity = raw as! SecIdentity
        var cert: SecCertificate?
        SecIdentityCopyCertificate(identity, &cert)
        guard let c = cert else { return ("Signing certificate", nil) }
        let summary = (SecCertificateCopySubjectSummary(c) as String?) ?? "Signing certificate"
        let info = CertificateInfo.parse(der: SecCertificateCopyData(c) as Data)
        return (info?.commonName.isEmpty == false ? info!.commonName : summary, info?.notAfter)
    }

    @discardableResult
    func importIdentity(p12: Data, profile profileData: Data, password: String, name: String? = nil) throws -> SigningIdentity {
        let profile: ProvisioningProfile
        do { profile = try ProvisioningProfile.parse(profileData) } catch { throw VaultError("That provisioning profile couldn't be read: \(error.localizedDescription)") }
        let cert = try Self.inspectP12(p12, password: password)
        let id = IDGen.short("id")
        let identity = SigningIdentity(id: id, name: name?.isEmpty == false ? name! : (profile.teamName.isEmpty ? cert.name : profile.teamName),
                                       createdAt: Date(), certificateName: cert.name, certificateExpiry: cert.expiry,
                                       profileName: profile.name, teamID: profile.teamID, teamName: profile.teamName,
                                       appIDPattern: profile.bundleIDPattern, profileExpiry: profile.expirationDate,
                                       kind: profile.kind.rawValue, deviceCount: profile.devices.count)
        try FileManager.default.createDirectory(at: identity.folder, withIntermediateDirectories: true)
        try p12.write(to: identity.p12URL, options: .completeFileProtection)
        try profileData.write(to: identity.profileURL)
        try JSONEncoder().encode(identity).write(to: identity.folder.appendingPathComponent("identity.json"))
        SecretStore.set(password, for: "sign.\(id)")
        reload()
        if AppSettings.shared.selectedSigningID.isEmpty || self.identity(AppSettings.shared.selectedSigningID) == nil {
            AppSettings.shared.selectedSigningID = id
        }
        return identity
    }

    /// Accepts a .p12 + .mobileprovision pair, or a .zip containing both (like ESign/Feather exports).
    @discardableResult
    func importFiles(_ urls: [URL], password: String, name: String? = nil) throws -> SigningIdentity {
        var p12: Data?
        var profile: Data?
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            if ext == "zip" {
                let zip = try ZipReader(url: url)
                for e in zip.entries where !e.isDirectory && !e.name.contains("__MACOSX") {
                    let lower = e.name.lowercased()
                    if lower.hasSuffix(".p12") || lower.hasSuffix(".pfx") { p12 = try zip.data(e) }
                    if lower.hasSuffix(".mobileprovision") { profile = try zip.data(e) }
                }
            } else if ext == "p12" || ext == "pfx" {
                p12 = try Data(contentsOf: url)
            } else if ext == "mobileprovision" {
                profile = try Data(contentsOf: url)
            } else {
                let d = try Data(contentsOf: url)
                if ProvisioningProfile.extractPlist(from: d) != nil { profile = d } else { p12 = d }
            }
        }
        guard let p = p12 else { throw VaultError("Add your certificate (.p12) — it wasn't in the selected files.") }
        guard let m = profile else { throw VaultError("Add your provisioning profile (.mobileprovision) — it wasn't in the selected files.") }
        return try importIdentity(p12: p, profile: m, password: password, name: name)
    }

    func delete(_ id: String) {
        guard let i = identity(id) else { return }
        try? FileManager.default.removeItem(at: i.folder)
        SecretStore.set(nil, for: "sign.\(id)")
        if AppSettings.shared.selectedSigningID == id { AppSettings.shared.selectedSigningID = "" }
        reload()
    }

    func rename(_ id: String, to name: String) {
        guard var i = identity(id) else { return }
        i.name = name
        try? JSONEncoder().encode(i).write(to: i.folder.appendingPathComponent("identity.json"))
        reload()
    }

    /// Asks Apple's OCSP responder whether the certificate has been revoked.
    func checkRevocation(_ identity: SigningIdentity) async {
        revocation[identity.id] = "Checking…"
        let prov = identity.profileURL.path, p12 = identity.p12URL.path, pw = identity.password
        let text: String = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                Zsign.checkRevokage(provisionPath: prov, p12Path: p12, p12Password: pw) { status, _, error in
                    switch status {
                    case 0: cont.resume(returning: "Valid — not revoked")
                    case 1: cont.resume(returning: "Revoked by Apple")
                    default: cont.resume(returning: error ?? "Status unknown")
                    }
                }
            }
        }
        revocation[identity.id] = text
    }
}
