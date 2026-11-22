import Foundation

/// Edits Info.plist files (binary or XML).
public struct PlistFile {
    public var dict: [String: Any]
    public var format: PropertyListSerialization.PropertyListFormat

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        var fmt = PropertyListSerialization.PropertyListFormat.binary
        guard let d = try PropertyListSerialization.propertyList(from: data, options: [.mutableContainersAndLeaves], format: &fmt) as? [String: Any] else {
            throw ZipError("\(url.lastPathComponent) is not a dictionary plist")
        }
        dict = d
        format = fmt
    }

    public init(dict: [String: Any]) { self.dict = dict; self.format = .binary }

    public func write(to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: format == .openStep ? .xml : format, options: 0)
        try data.write(to: url, options: .atomic)
    }

    public subscript(key: String) -> Any? {
        get { dict[key] }
        set { dict[key] = newValue }
    }
}

public struct AssemblyOptions {
    public var bundleID: String
    public var displayName: String
    public var version: String
    public var build: String
    public var includeWidget: Bool
    public var urlScheme: String
    public var appearance: Theme.Appearance
    /// File name → PNG data (rendered by the app: AppIcon60x60@2x.png, …).
    public var icons: [String: Data]
    public var projectJSON: Data
    /// Imported images (asset id → file data).
    public var assets: [String: Data]

    public init(project: Project, icons: [String: Data] = [:], assets: [String: Data] = [:], includeWidget: Bool? = nil) throws {
        bundleID = project.bundleID
        displayName = project.brand.displayName
        version = project.version
        build = String(project.build)
        self.includeWidget = includeWidget ?? project.widget.enabled
        urlScheme = "rf" + BundleID.slug(project.bundleID).prefix(24)
        appearance = project.theme.appearance
        self.icons = icons
        projectJSON = try project.jsonData(pretty: false)
        self.assets = assets
    }
}

public enum AppAssembler {
    public static let runtimeExecutable = "ReyForgeRuntime"
    public static let projectFileName = "ReyForgeProject.json"
    public static let assetsFolder = "ReyForgeAssets"
    public static let widgetBundleName = "ReyForgeWidget.appex"

    /// Standard loose icon files referenced from Info.plist (no asset catalog compilation needed on device).
    public static let iconSizes: [(file: String, pixels: Int)] = [
        ("AppIcon60x60@2x.png", 120), ("AppIcon60x60@3x.png", 180),
        ("AppIcon76x76@2x~ipad.png", 152), ("AppIcon83.5x83.5@2x~ipad.png", 167),
        ("AppIcon40x40@2x.png", 80), ("AppIcon40x40@3x.png", 120),
    ]

    public static func safeAppName(_ name: String) -> String {
        let cleaned = name.filter { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" }.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "App" : String(cleaned.prefix(40))
    }

    /// Builds `<workDir>/Payload/<Name>.app` from the runtime template. Returns the app folder.
    @discardableResult
    public static func assemble(templateApp: URL, workDir: URL, options o: AssemblyOptions) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: templateApp.appendingPathComponent("Info.plist").path) else {
            throw ZipError("The runtime template is missing. Reinstall ReyForge or use Cloud Build.")
        }
        guard BundleID.isValid(o.bundleID) else { throw ZipError("“\(o.bundleID)” is not a valid bundle identifier.") }
        let payload = workDir.appendingPathComponent("Payload")
        try? fm.removeItem(at: payload)
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        let app = payload.appendingPathComponent(safeAppName(o.displayName) + ".app")
        try fm.copyItem(at: templateApp, to: app)

        // Old signatures are invalid after editing; the signer creates fresh ones.
        for leftover in ["_CodeSignature", "embedded.mobileprovision", "SC_Info"] {
            try? fm.removeItem(at: app.appendingPathComponent(leftover))
        }

        // Project and assets.
        try o.projectJSON.write(to: app.appendingPathComponent(projectFileName))
        if !o.assets.isEmpty {
            let dir = app.appendingPathComponent(assetsFolder)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for (name, data) in o.assets { try data.write(to: dir.appendingPathComponent(name)) }
        }

        // Icons.
        for (file, data) in o.icons { try data.write(to: app.appendingPathComponent(file)) }

        // Info.plist.
        let plistURL = app.appendingPathComponent("Info.plist")
        var plist = try PlistFile(url: plistURL)
        patchMain(&plist, o)
        try plist.write(to: plistURL)

        // Widget extension.
        let widget = app.appendingPathComponent("PlugIns").appendingPathComponent(widgetBundleName)
        if fm.fileExists(atPath: widget.path) {
            if o.includeWidget {
                try? fm.removeItem(at: widget.appendingPathComponent("_CodeSignature"))
                try? fm.removeItem(at: widget.appendingPathComponent("embedded.mobileprovision"))
                try o.projectJSON.write(to: widget.appendingPathComponent(projectFileName))
                let wURL = widget.appendingPathComponent("Info.plist")
                var w = try PlistFile(url: wURL)
                w["CFBundleIdentifier"] = o.bundleID + ".widget"
                w["CFBundleDisplayName"] = o.displayName
                w["CFBundleShortVersionString"] = o.version
                w["CFBundleVersion"] = o.build
                try w.write(to: wURL)
            } else {
                try fm.removeItem(at: widget)
                let plugins = app.appendingPathComponent("PlugIns")
                if (try? fm.contentsOfDirectory(atPath: plugins.path))?.isEmpty == true { try? fm.removeItem(at: plugins) }
            }
        }
        // Make sure the executable stays executable.
        let exe = app.appendingPathComponent((plist["CFBundleExecutable"] as? String) ?? runtimeExecutable)
        if fm.fileExists(atPath: exe.path) { try? fm.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: exe.path) }
        return app
    }

    static func patchMain(_ p: inout PlistFile, _ o: AssemblyOptions) {
        p["CFBundleIdentifier"] = o.bundleID
        p["CFBundleDisplayName"] = o.displayName
        p["CFBundleName"] = String(o.displayName.prefix(15))
        p["CFBundleShortVersionString"] = o.version
        p["CFBundleVersion"] = o.build
        if !o.icons.isEmpty {
            let phone = ["AppIcon60x60", "AppIcon40x40"]
            p["CFBundleIcons"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": phone]]
            p["CFBundleIcons~ipad"] = ["CFBundlePrimaryIcon": ["CFBundleIconFiles": phone + ["AppIcon76x76", "AppIcon83.5x83.5"]]]
            p["CFBundleIconName"] = nil
        }
        switch o.appearance {
        case .dark: p["UIUserInterfaceStyle"] = "Dark"
        case .light: p["UIUserInterfaceStyle"] = "Light"
        case .system: p["UIUserInterfaceStyle"] = nil
        }
        p["CFBundleURLTypes"] = [["CFBundleURLName": o.bundleID, "CFBundleURLSchemes": [o.urlScheme]]]
        p["ReyForgeBuiltAt"] = ISO8601DateFormatter().string(from: Date())
    }

    /// Zips `<workDir>/Payload` into an IPA.
    public static func packageIPA(workDir: URL, to ipa: URL) throws {
        try? FileManager.default.removeItem(at: ipa)
        let w = try ZipWriter(url: ipa)
        try w.addDirectoryContents(of: workDir.appendingPathComponent("Payload"), prefix: "Payload")
        try w.finish()
    }

    /// Reads identity information from an IPA without extracting it all.
    public struct IPAInfo: Hashable {
        public var bundleID: String
        public var displayName: String
        public var version: String
        public var build: String
        public var executable: String
        public var appFolder: String
    }

    public static func inspect(ipa: URL) throws -> IPAInfo {
        let zip = try ZipReader(url: ipa)
        guard let entry = zip.entries.first(where: { e in
            let parts = e.name.split(separator: "/")
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }) else { throw ZipError("The IPA must contain Payload/<App>.app/Info.plist.") }
        let data = try zip.data(entry)
        guard let d = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw ZipError("Unreadable Info.plist") }
        let folder = String(entry.name.split(separator: "/")[1])
        return IPAInfo(bundleID: d["CFBundleIdentifier"] as? String ?? "", displayName: d["CFBundleDisplayName"] as? String ?? d["CFBundleName"] as? String ?? folder,
                       version: d["CFBundleShortVersionString"] as? String ?? "1.0", build: d["CFBundleVersion"] as? String ?? "1",
                       executable: d["CFBundleExecutable"] as? String ?? "", appFolder: folder)
    }

    /// Rewrites an extracted app's identity (for re-signing an imported IPA), including nested extensions
    /// whose identifiers share the original prefix — the same approach Feather and ReyForge 2.x used.
    public static func rewriteIdentity(app: URL, bundleID: String, displayName: String?) throws {
        let plistURL = app.appendingPathComponent("Info.plist")
        var p = try PlistFile(url: plistURL)
        let old = p["CFBundleIdentifier"] as? String ?? ""
        p["CFBundleIdentifier"] = bundleID
        if let n = displayName, !n.isEmpty { p["CFBundleDisplayName"] = n }
        try p.write(to: plistURL)
        guard !old.isEmpty, old != bundleID else { return }
        let fm = FileManager.default
        for dirName in ["PlugIns", "Extensions", "Watch", "AppClips"] {
            let dir = app.appendingPathComponent(dirName)
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "appex" || item.pathExtension == "app" {
                let u = item.appendingPathComponent("Info.plist")
                guard var ep = try? PlistFile(url: u), let id = ep["CFBundleIdentifier"] as? String else { continue }
                if id.hasPrefix(old) { ep["CFBundleIdentifier"] = bundleID + id.dropFirst(old.count) }
                if var ext = ep["NSExtension"] as? [String: Any], var attrs = ext["NSExtensionAttributes"] as? [String: Any],
                   let wk = attrs["WKAppBundleIdentifier"] as? String, wk.hasPrefix(old) {
                    attrs["WKAppBundleIdentifier"] = bundleID + wk.dropFirst(old.count)
                    ext["NSExtensionAttributes"] = attrs
                    ep["NSExtension"] = ext
                }
                if let companion = ep["WKCompanionAppBundleIdentifier"] as? String, companion == old { ep["WKCompanionAppBundleIdentifier"] = bundleID }
                try ep.write(to: u)
            }
        }
    }
}
