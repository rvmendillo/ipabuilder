import Foundation

/// A parsed `.mobileprovision` (a CMS-signed property list).
public struct ProvisioningProfile: Hashable {
    public enum Kind: String { case development = "Development", adHoc = "Ad Hoc", enterprise = "Enterprise", appStore = "App Store" }

    public var name: String
    public var uuid: String
    public var teamID: String
    public var teamName: String
    public var appIDName: String
    public var applicationIdentifier: String
    public var creationDate: Date?
    public var expirationDate: Date?
    public var devices: [String]
    public var provisionsAllDevices: Bool
    public var entitlements: [String: Value]
    public var certificates: [CertificateInfo]

    public var kind: Kind {
        if provisionsAllDevices { return .enterprise }
        if entitlements["get-task-allow"]?.boolValue == true { return .development }
        return devices.isEmpty ? .appStore : .adHoc
    }

    /// The bundle-id part of the application identifier ("com.example.*").
    public var bundleIDPattern: String {
        if let dot = applicationIdentifier.firstIndex(of: "."), applicationIdentifier[..<dot] == Substring(teamID) || applicationIdentifier[..<dot].count == 10 {
            return String(applicationIdentifier[applicationIdentifier.index(after: dot)...])
        }
        return applicationIdentifier
    }

    public var isWildcard: Bool { bundleIDPattern.hasSuffix("*") }
    public var isExpired: Bool { (expirationDate ?? .distantFuture) < Date() }

    public func allows(bundleID: String) -> Bool { BundleID.matches(pattern: applicationIdentifier, bundleID: bundleID) }

    /// Widget extensions need their own bundle id (`app.widget`), which only wildcard profiles cover.
    public func allowsExtension(of bundleID: String) -> Bool { allows(bundleID: bundleID + ".widget") }

    public var daysRemaining: Int? {
        expirationDate.map { Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 0 }
    }

    /// Extracts the embedded XML plist from the CMS envelope.
    public static func extractPlist(from data: Data) -> Data? {
        guard let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8), in: start.upperBound..<data.endIndex) else {
            // Some tools write a bare plist.
            if (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil { return data }
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }

    public static func parse(_ data: Data) throws -> ProvisioningProfile {
        guard let plistData = extractPlist(from: data),
              let dict = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw ZipError("This provisioning profile could not be read.")
        }
        let ent = dict["Entitlements"] as? [String: Any] ?? [:]
        var entitlements: [String: Value] = [:]
        for (k, v) in ent { entitlements[k] = Value(any: v) }
        let teams = dict["TeamIdentifier"] as? [String] ?? []
        let teamID = teams.first ?? (ent["com.apple.developer.team-identifier"] as? String ?? "")
        let certs = (dict["DeveloperCertificates"] as? [Data] ?? []).compactMap { CertificateInfo.parse(der: $0) }
        return ProvisioningProfile(
            name: dict["Name"] as? String ?? "Provisioning Profile",
            uuid: dict["UUID"] as? String ?? "",
            teamID: teamID,
            teamName: dict["TeamName"] as? String ?? "",
            appIDName: dict["AppIDName"] as? String ?? "",
            applicationIdentifier: ent["application-identifier"] as? String ?? (teamID.isEmpty ? "*" : teamID + ".*"),
            creationDate: dict["CreationDate"] as? Date,
            expirationDate: dict["ExpirationDate"] as? Date,
            devices: dict["ProvisionedDevices"] as? [String] ?? [],
            provisionsAllDevices: dict["ProvisionsAllDevices"] as? Bool ?? false,
            entitlements: entitlements,
            certificates: certs)
    }

    /// Human readable problems that will block installation.
    public func problems(for bundleID: String, includeWidget: Bool) -> [String] {
        var out: [String] = []
        if isExpired { out.append("The provisioning profile “\(name)” expired on \(expirationDate.map { ProvisioningProfile.dateFormatter.string(from: $0) } ?? "an earlier date"). Import a current one.") }
        if !allows(bundleID: bundleID) {
            out.append("The profile permits \(bundleIDPattern), not \(bundleID). Change the app's bundle ID in Build settings or import a matching (or wildcard) profile.")
        }
        if includeWidget && !allowsExtension(of: bundleID) {
            out.append("The widget needs \(bundleID).widget, which this explicit profile doesn't cover. Use a wildcard profile or turn the widget off.")
        }
        return out
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()
}

// MARK: - X.509 (just enough DER to show the certificate name and validity)

public struct CertificateInfo: Hashable {
    public var commonName: String
    public var organization: String
    public var notBefore: Date?
    public var notAfter: Date?
    public var serialHex: String

    public var isExpired: Bool { (notAfter ?? .distantFuture) < Date() }

    public static func parse(der: Data) -> CertificateInfo? {
        var r = DERReader(Array(der))
        guard let cert = r.readTLV(), cert.tag == 0x30 else { return nil }
        var c = DERReader(cert.value)
        guard let tbs = c.readTLV(), tbs.tag == 0x30 else { return nil }
        var t = DERReader(tbs.value)
        var next = t.readTLV()
        if next?.tag == 0xA0 { next = t.readTLV() }          // version
        let serial = next?.value ?? []                           // serial number
        _ = t.readTLV()                                          // signature algorithm
        _ = t.readTLV()                                          // issuer
        var notBefore: Date?, notAfter: Date?
        if let validity = t.readTLV(), validity.tag == 0x30 {
            var v = DERReader(validity.value)
            notBefore = v.readTLV().flatMap(DERReader.date)
            notAfter = v.readTLV().flatMap(DERReader.date)
        }
        var cn = "", org = ""
        if let subject = t.readTLV(), subject.tag == 0x30 {
            var s = DERReader(subject.value)
            while let set = s.readTLV() {
                var sr = DERReader(set.value)
                while let atv = sr.readTLV() {
                    var a = DERReader(atv.value)
                    guard let oid = a.readTLV(), let val = a.readTLV() else { continue }
                    let str = String(bytes: val.value, encoding: .utf8) ?? ""
                    if oid.value == [0x55, 0x04, 0x03] { cn = str }
                    if oid.value == [0x55, 0x04, 0x0A] { org = str }
                }
            }
        }
        return CertificateInfo(commonName: cn, organization: org, notBefore: notBefore, notAfter: notAfter,
                               serialHex: serial.map { String(format: "%02X", $0) }.joined())
    }
}

struct DERReader {
    struct TLV { var tag: UInt8; var value: [UInt8] }
    let bytes: [UInt8]
    var pos = 0
    init(_ b: [UInt8]) { bytes = b }

    mutating func readTLV() -> TLV? {
        guard pos + 2 <= bytes.count else { return nil }
        let tag = bytes[pos]; pos += 1
        var len = Int(bytes[pos]); pos += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, n <= 4, pos + n <= bytes.count else { return nil }
            len = 0
            for _ in 0..<n { len = (len << 8) | Int(bytes[pos]); pos += 1 }
        }
        guard len >= 0, pos + len <= bytes.count else { return nil }
        let value = Array(bytes[pos..<(pos + len)])
        pos += len
        return TLV(tag: tag, value: value)
    }

    static func date(_ tlv: TLV) -> Date? {
        guard let s = String(bytes: tlv.value, encoding: .ascii) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = tlv.tag == 0x17 ? "yyMMddHHmmss'Z'" : "yyyyMMddHHmmss'Z'"
        return f.date(from: s)
    }
}
