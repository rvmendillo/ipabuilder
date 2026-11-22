import XCTest
@testable import ReyForgeCore

final class ZipTests: XCTestCase {
    var tmp: URL!
    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rf-zip-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testCRC32KnownValues() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
        XCTAssertEqual(CRC32.checksum(Data()), 0)
        var big = Data(count: 1_000_003)
        for i in 0..<big.count { big[i] = UInt8(i % 251) }
        var c = CRC32(); c.update(big.prefix(500_000)); c.update(big.suffix(from: 500_000))
        XCTAssertEqual(c.checksum, CRC32.checksum(big), "streaming matches one-shot")
    }

    func testRoundTripPreservesContentPermissionsAndLayout() throws {
        let src = tmp.appendingPathComponent("src/Payload/Demo.app")
        try FileManager.default.createDirectory(at: src.appendingPathComponent("Frameworks/X.framework"), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: src.appendingPathComponent("Demo"))
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: src.appendingPathComponent("Demo").path)
        let big = Data((0..<300_000).map { UInt8($0 % 7) })
        try big.write(to: src.appendingPathComponent("Frameworks/X.framework/X"))
        try Data("ünïcødé".utf8).write(to: src.appendingPathComponent("Résumé.txt"))
        let ipa = tmp.appendingPathComponent("Demo.ipa")
        let w = try ZipWriter(url: ipa)
        try w.addDirectoryContents(of: tmp.appendingPathComponent("src/Payload"), prefix: "Payload")
        try w.finish()

        let r = try ZipReader(url: ipa)
        XCTAssertNotNil(r.entry(named: "Payload/Demo.app/Demo"))
        XCTAssertNotNil(r.entry(named: "Payload/Demo.app/Résumé.txt"))
        XCTAssertEqual(try r.data(r.entry(named: "Payload/Demo.app/Frameworks/X.framework/X")!), big)
        // Local headers carry real sizes (no data descriptors) for streaming installers.
        let raw = try Data(contentsOf: ipa)
        let e = r.entry(named: "Payload/Demo.app/Demo")!
        let flags = UInt16(raw[Int(e.localHeaderOffset) + 6]) | UInt16(raw[Int(e.localHeaderOffset) + 7]) << 8
        XCTAssertEqual(flags & 0x0008, 0)
        XCTAssertEqual(ZipReader.u32(raw, Int(e.localHeaderOffset) + 22), 6)

        let out = tmp.appendingPathComponent("out")
        try r.extractAll(to: out)
        let exe = out.appendingPathComponent("Payload/Demo.app/Demo")
        XCTAssertEqual(try Data(contentsOf: exe), Data("binary".utf8))
        let mode = (try FileManager.default.attributesOfItem(atPath: exe.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o755)
    }

    func testRejectsPathTraversal() throws {
        let evil = tmp.appendingPathComponent("evil.zip")
        let w = try ZipWriter(url: evil)
        try w.addData("../escape.txt", Data("x".utf8))
        try w.finish()
        XCTAssertThrowsError(try ZipReader(url: evil).extractAll(to: tmp.appendingPathComponent("dest")))
    }
}

final class SigningMaterialTests: XCTestCase {
    func testParsesCMSSignedProfile() throws {
        let p = try ProvisioningProfile.parse(FixtureData.mobileprovision)
        XCTAssertEqual(p.name, "ReyForge Test Ad Hoc")
        XCTAssertEqual(p.teamID, "ABCDE12345")
        XCTAssertEqual(p.teamName, "ReyForge Test")
        XCTAssertEqual(p.uuid, "9F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0")
        XCTAssertEqual(p.devices.count, 2)
        XCTAssertEqual(p.kind, .adHoc)
        XCTAssertTrue(p.isWildcard)
        XCTAssertTrue(p.allows(bundleID: "com.rvmendillo.anything"))
        XCTAssertTrue(p.allowsExtension(of: "com.rvmendillo.anything"))
        XCTAssertFalse(p.isExpired)
        XCTAssertEqual(p.certificates.first?.commonName, "Apple Distribution: ReyForge Test (ABCDE12345)")
        XCTAssertEqual(p.certificates.first?.organization, "ReyForge Test")
        XCTAssertNotNil(p.certificates.first?.notAfter)
        XCTAssertTrue(p.problems(for: "com.x.y", includeWidget: true).isEmpty)
    }

    func testExplicitProfileProblems() throws {
        var p = try ProvisioningProfile.parse(FixtureData.mobileprovision)
        p.applicationIdentifier = "ABCDE12345.com.rvmendillo.reyforge"
        XCTAssertFalse(p.isWildcard)
        XCTAssertTrue(p.allows(bundleID: "com.rvmendillo.reyforge"))
        XCTAssertFalse(p.allows(bundleID: "com.rvmendillo.other"))
        let problems = p.problems(for: "com.rvmendillo.reyforge", includeWidget: true)
        XCTAssertEqual(problems.count, 1)
        XCTAssertTrue(problems[0].contains("widget"))
        p.expirationDate = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(p.problems(for: "com.rvmendillo.reyforge", includeWidget: false).first!.contains("expired"))
    }

    func testRejectsGarbage() {
        XCTAssertThrowsError(try ProvisioningProfile.parse(Data("not a profile".utf8)))
    }
}

final class AssemblerTests: XCTestCase {
    var tmp: URL!
    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rf-asm-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    /// A stand-in for the precompiled runtime app produced by CI.
    func makeTemplate() throws -> URL {
        let app = tmp.appendingPathComponent("ReyForgeRuntime.app")
        let widget = app.appendingPathComponent("PlugIns/ReyForgeWidget.appex")
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("_CodeSignature"), withIntermediateDirectories: true)
        try Data("exe".utf8).write(to: app.appendingPathComponent("ReyForgeRuntime"))
        try PlistFile(dict: ["CFBundleIdentifier": "com.reyforge.runtime", "CFBundleExecutable": "ReyForgeRuntime", "CFBundleName": "ReyForgeRuntime",
                             "CFBundleIconName": "AppIcon", "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]).write(to: app.appendingPathComponent("Info.plist"))
        try PlistFile(dict: ["CFBundleIdentifier": "com.reyforge.runtime.widget", "CFBundleExecutable": "ReyForgeWidget"]).write(to: widget.appendingPathComponent("Info.plist"))
        return app
    }

    func testAssemblesBrandedApp() throws {
        var project = Templates.template("coffee")!.makeProject(named: "Bean There")
        project.bundleID = "com.rvmendillo.beanthere"
        project.version = "2.1"
        project.build = 7
        project.theme.appearance = .dark
        let icons = Dictionary(uniqueKeysWithValues: AppAssembler.iconSizes.map { ($0.file, Data("png\($0.pixels)".utf8)) })
        let options = try AssemblyOptions(project: project, icons: icons, assets: ["logo.png": Data([1, 2, 3])])
        let app = try AppAssembler.assemble(templateApp: try makeTemplate(), workDir: tmp.appendingPathComponent("work"), options: options)
        XCTAssertEqual(app.lastPathComponent, "Bean There.app")
        let plist = try PlistFile(url: app.appendingPathComponent("Info.plist"))
        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.rvmendillo.beanthere")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Bean There")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "2.1")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "7")
        XCTAssertEqual(plist["UIUserInterfaceStyle"] as? String, "Dark")
        XCTAssertNil(plist["CFBundleIconName"], "asset-catalog icon removed so the generated icon is used")
        XCTAssertNotNil(plist["CFBundleIcons"])
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "ReyForgeRuntime")
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("_CodeSignature").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("AppIcon60x60@3x.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("ReyForgeAssets/logo.png").path))
        let embedded = try Project.decode(try Data(contentsOf: app.appendingPathComponent(AppAssembler.projectFileName)))
        XCTAssertEqual(embedded.brand.displayName, "Bean There")
        // Widget kept (template enables it) and re-identified.
        let w = try PlistFile(url: app.appendingPathComponent("PlugIns/ReyForgeWidget.appex/Info.plist"))
        XCTAssertEqual(w["CFBundleIdentifier"] as? String, "com.rvmendillo.beanthere.widget")
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("PlugIns/ReyForgeWidget.appex/\(AppAssembler.projectFileName)").path))

        let ipa = tmp.appendingPathComponent("BeanThere.ipa")
        try AppAssembler.packageIPA(workDir: tmp.appendingPathComponent("work"), to: ipa)
        let info = try AppAssembler.inspect(ipa: ipa)
        XCTAssertEqual(info.bundleID, "com.rvmendillo.beanthere")
        XCTAssertEqual(info.displayName, "Bean There")
        XCTAssertEqual(info.appFolder, "Bean There.app")
    }

    func testWidgetRemovedWhenDisabled() throws {
        var project = Templates.template("blank")!.makeProject()
        project.widget.enabled = false
        let app = try AppAssembler.assemble(templateApp: try makeTemplate(), workDir: tmp.appendingPathComponent("w2"), options: try AssemblyOptions(project: project))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("PlugIns").path))
    }

    func testRejectsInvalidBundleID() throws {
        var project = Templates.template("blank")!.makeProject()
        project.bundleID = "nope"
        XCTAssertThrowsError(try AppAssembler.assemble(templateApp: try makeTemplate(), workDir: tmp.appendingPathComponent("w3"), options: try AssemblyOptions(project: project)))
    }

    func testRewriteIdentityUpdatesExtensions() throws {
        let app = try makeTemplate()
        try AppAssembler.rewriteIdentity(app: app, bundleID: "com.me.new", displayName: "New")
        XCTAssertEqual(try PlistFile(url: app.appendingPathComponent("Info.plist"))["CFBundleIdentifier"] as? String, "com.me.new")
        XCTAssertEqual(try PlistFile(url: app.appendingPathComponent("PlugIns/ReyForgeWidget.appex/Info.plist"))["CFBundleIdentifier"] as? String, "com.me.new.widget")
    }
}

final class InstallTests: XCTestCase {
    func testHTTPParsing() {
        let raw = Data("GET /app.ipa?token=a%20b HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-99\r\n\r\n".utf8)
        guard case .request(let r) = MiniHTTP.parse(raw) else { return XCTFail() }
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.path, "/app.ipa")
        XCTAssertEqual(r.query["token"], "a b")
        XCTAssertEqual(r.headers["range"], "bytes=0-99")
        XCTAssertEqual(MiniHTTP.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)), .incomplete)
        XCTAssertEqual(MiniHTTP.parse(Data(repeating: 65, count: 20_000)), .tooLarge)
    }

    func testRanges() {
        XCTAssertEqual(MiniHTTP.range(nil, size: 1000), .full)
        XCTAssertEqual(MiniHTTP.range("bytes=0-99", size: 1000), .partial(start: 0, end: 99))
        XCTAssertEqual(MiniHTTP.range("bytes=900-", size: 1000), .partial(start: 900, end: 999))
        XCTAssertEqual(MiniHTTP.range("bytes=-100", size: 1000), .partial(start: 900, end: 999))
        XCTAssertEqual(MiniHTTP.range("bytes=500-5000", size: 1000), .partial(start: 500, end: 999))
        XCTAssertEqual(MiniHTTP.range("bytes=1000-", size: 1000), .unsatisfiable)
        let head = MiniHTTP.fileHead(range: .partial(start: 10, end: 19), size: 100, contentType: "application/octet-stream")!
        let text = String(data: head.0, encoding: .utf8)!
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 206 Partial Content"))
        XCTAssertTrue(text.contains("Content-Range: bytes 10-19/100"))
        XCTAssertEqual(head.1, 10); XCTAssertEqual(head.2, 10)
    }

    func testInstallLinksMatchReyForge2Format() {
        let manifest = InstallLinks.manifestURL(bundleID: "com.test.app", name: "Test App", version: "1.0", ipaURL: "http://127.0.0.1:1234/app.ipa")!
        XCTAssertEqual(manifest.absoluteString, "https://api.palera.in/genPlist?bundleid=com.test.app&name=Test%20App&version=1.0&fetchurl=http%3A%2F%2F127.0.0.1%3A1234%2Fapp.ipa")
        let itms = InstallLinks.itmsServices(manifest: manifest)!.absoluteString
        XCTAssertTrue(itms.hasPrefix("itms-services://?action=download-manifest&url=https%3A%2F%2Fapi.palera.in%2FgenPlist%3Fbundleid%3D"))
        XCTAssertFalse(itms.dropFirst(50).contains("&"), "the whole manifest URL is encoded into one parameter")
        let plist = InstallLinks.manifestPlist(bundleID: "com.test.app", name: "Test", version: "1.0", ipaURL: "https://x/app.ipa")
        let obj = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        XCTAssertNotNil(obj?["items"])
    }

    func testReleaseSelectionAndVersions() throws {
        let json = """
        {"id":1,"tag_name":"v3.0.12","name":"ReyForge 3.0.12","body":"Notes","html_url":"https://github.com/rvmendillo/ipabuilder/releases/tag/v3.0.12","published_at":"2026-11-22T00:00:00Z","prerelease":false,
         "assets":[{"id":11,"name":"ReyForge-3.0.12.ipa","size":1300000000,"browser_download_url":"https://github.com/x/ReyForge-3.0.12.ipa","url":"https://api.github.com/x/11"},
                   {"id":12,"name":"ReyForge-3.0.12-lite.ipa","size":30000000,"browser_download_url":"https://github.com/x/ReyForge-3.0.12-lite.ipa","url":"https://api.github.com/x/12"},
                   {"id":13,"name":"manifest.plist","size":800,"browser_download_url":"https://github.com/x/manifest.plist","url":"https://api.github.com/x/13"}]}
        """
        let r = try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
        XCTAssertEqual(r.version, "3.0.12")
        XCTAssertEqual(r.ipaAsset(preferLite: true)?.id, 12)
        XCTAssertEqual(r.ipaAsset(preferLite: false)?.id, 11)
        XCTAssertTrue(SemVer.isNewer("3.0.12", than: "3.0.9"))
        XCTAssertFalse(SemVer.isNewer("3.0", than: "3.0.0"))
        XCTAssertTrue(SemVer.isNewer("3.1", than: "2.7"))
        let client = GitHubClient(owner: "rvmendillo", repo: "ipabuilder", token: "t")
        let req = try client.request("/repos/rvmendillo/ipabuilder/actions/workflows/ipa-builder-service.yml/dispatches", method: "POST", body: ["ref": "main"])
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        XCTAssertEqual(req.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
    }
}
