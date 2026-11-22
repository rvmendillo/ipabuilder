import XCTest
import ReyForgeCore
import Zsign
@testable import ReyForge

/// End-to-end tests of the on-device build pipeline running inside the iOS Simulator.
@MainActor
final class BuildPipelineTests: XCTestCase {
    var vault: SigningVault { SigningVault.shared }

    func testRuntimeTemplateIsEmbedded() throws {
        let app = try BuildService.runtimeTemplate()
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Info.plist").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent(AppAssembler.runtimeExecutable).path), "runtime executable present")
        let plugins = app.appendingPathComponent("PlugIns").appendingPathComponent(AppAssembler.widgetBundleName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: plugins.path), "widget extension present in the template")
    }

    func testIconRendering() {
        let p = Templates.template("fitness")!.makeProject(named: "Icons")
        let pngs = AppIconView.renderPNGs(icon: p.brand.icon, theme: p.theme)
        XCTAssertEqual(pngs.count, AppAssembler.iconSizes.count)
        for (file, px) in AppAssembler.iconSizes {
            guard let data = pngs[file], let img = UIImage(data: data) else { return XCTFail("missing \(file)") }
            XCTAssertEqual(Int(img.size.width * img.scale), px, file)
        }
    }

    func testUnsignedBuildProducesInstallableLayout() async throws {
        var p = Templates.template("tasks")!.makeProject(named: "Unit Tasks")
        p.bundleID = "com.reyforge.unittests.tasks"
        p.widget.enabled = true
        let service = BuildService()
        await service.build(project: p, assets: [:], identity: nil, includeWidget: true)
        XCTAssertNil(service.error, service.log.joined(separator: "\n"))
        let r = try XCTUnwrap(service.result)
        XCTAssertFalse(r.signed)
        XCTAssertEqual(r.bundleID, "com.reyforge.unittests.tasks")
        let zip = try ZipReader(url: r.ipa)
        let names = Set(zip.entries.map(\.name))
        XCTAssertTrue(names.contains { $0.hasSuffix("/\(AppAssembler.projectFileName)") })
        XCTAssertTrue(names.contains { $0.hasSuffix("/AppIcon60x60@2x.png") })
        XCTAssertTrue(names.contains { $0.contains("PlugIns/\(AppAssembler.widgetBundleName)/Info.plist") })
        // The embedded project round-trips.
        let entry = try XCTUnwrap(zip.entries.first { $0.name.hasSuffix("/\(AppAssembler.projectFileName)") })
        let embedded = try Project.decode(try zip.data(entry))
        XCTAssertEqual(embedded.screens.count, p.screens.count)
        try? FileManager.default.removeItem(at: r.ipa)
    }

    func testSigningWithImportedIdentity() async throws {
        // Import the test certificate + wildcard profile like a user would.
        let identity = try vault.importIdentity(p12: FixtureData.p12, profile: FixtureData.mobileprovision, password: FixtureData.p12Password, name: "Unit Test")
        defer { vault.delete(identity.id) }
        XCTAssertTrue(identity.isWildcard)
        XCTAssertEqual(identity.teamID, "ABCDE12345")
        XCTAssertEqual(identity.password, FixtureData.p12Password)

        var p = Templates.template("weather")!.makeProject(named: "Signed Weather")
        p.bundleID = "com.reyforge.unittests.weather"
        let service = BuildService()
        await service.build(project: p, assets: [:], identity: identity, includeWidget: true)
        XCTAssertNil(service.error, service.log.joined(separator: "\n"))
        let r = try XCTUnwrap(service.result)
        XCTAssertTrue(r.signed)

        // Unpack and verify the signature zsign produced.
        let out = Paths.scratch("verify")
        try ZipReader(url: r.ipa).extractAll(to: out)
        let app = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: out.appendingPathComponent("Payload"), includingPropertiesForKeys: nil).first { $0.pathExtension == "app" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("_CodeSignature/CodeResources").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("embedded.mobileprovision").path))
        XCTAssertTrue(Zsign.checkSigned(appExecutable: app.appendingPathComponent(AppAssembler.runtimeExecutable).path))
        try? FileManager.default.removeItem(at: out)
        try? FileManager.default.removeItem(at: r.ipa)
    }

    func testWrongPasswordIsRejected() {
        XCTAssertThrowsError(try vault.importIdentity(p12: FixtureData.p12, profile: FixtureData.mobileprovision, password: "wrong", name: "Bad"))
    }

    func testImportFromZipBundle() throws {
        let dir = Paths.scratch("zipimport")
        let zipURL = dir.appendingPathComponent("signing.zip")
        let w = try ZipWriter(url: zipURL)
        try w.addData("cert.p12", FixtureData.p12)
        try w.addData("profile.mobileprovision", FixtureData.mobileprovision)
        try w.finish()
        let identity = try vault.importFiles([zipURL], password: FixtureData.p12Password)
        XCTAssertEqual(identity.profileName, "ReyForge Test Ad Hoc")
        vault.delete(identity.id)
    }
}

/// The localhost server that feeds IPAs to the iOS installer.
final class InstallServerTests: XCTestCase {
    func testServesFilesWithRanges() async throws {
        let dir = Paths.scratch("serve")
        let file = dir.appendingPathComponent("app.ipa")
        let payload = Data((0..<300_000).map { UInt8($0 % 251) })
        try payload.write(to: file)
        let url = try await InstallServer.shared.serve(file, at: "/test.ipa")
        XCTAssertEqual(url.host, "127.0.0.1")

        let (full, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(full, payload)

        var ranged = URLRequest(url: url)
        ranged.setValue("bytes=1000-1999", forHTTPHeaderField: "Range")
        let (part, r2) = try await URLSession.shared.data(for: ranged)
        XCTAssertEqual((r2 as? HTTPURLResponse)?.statusCode, 206)
        XCTAssertEqual(part, payload.subdata(in: 1000..<2000))

        let missing = URL(string: "http://127.0.0.1:\(url.port!)/nope")!
        let (_, r3) = try await URLSession.shared.data(from: missing)
        XCTAssertEqual((r3 as? HTTPURLResponse)?.statusCode, 404)
        InstallServer.shared.stop()
    }

    func testInstallLinksPointAtLocalhost() {
        let manifest = InstallLinks.manifestURL(bundleID: "com.x.y", name: "My App", version: "1.0", ipaURL: "http://127.0.0.1:8080/app.ipa")!
        XCTAssertTrue(manifest.absoluteString.contains("fetchurl=http%3A%2F%2F127.0.0.1%3A8080%2Fapp.ipa"))
        let itms = InstallLinks.itmsServices(manifest: manifest)!
        XCTAssertEqual(itms.scheme, "itms-services")
    }
}
