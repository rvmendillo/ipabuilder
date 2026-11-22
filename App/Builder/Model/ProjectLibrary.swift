import Foundation
import SwiftUI
import UniformTypeIdentifiers
import ReyForgeCore

struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    var name: String
    var updatedAt: Date
    var icon: IconSpec
    var theme: Theme
    var screenCount: Int
    var templateID: String?
}

extension UTType {
    static let reyforgeProject = UTType(exportedAs: "com.rvmendillo.reyforge.project", conformingTo: .zip)
}

/// Stores projects as folders: Projects/<id>/project.json + assets/.
@MainActor
final class ProjectLibrary: ObservableObject {
    @Published private(set) var projects: [ProjectSummary] = []
    @Published var openProject: Project?
    @Published var message: String?

    init() {
        Paths.resetForUITests()
        migrateLegacyIfNeeded()
        reload()
    }

    func folder(for id: UUID) -> URL { Paths.projects.appendingPathComponent(id.uuidString, isDirectory: true) }
    func assetsFolder(for id: UUID) -> URL {
        let url = folder(for: id).appendingPathComponent("assets", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func file(for id: UUID) -> URL { folder(for: id).appendingPathComponent("project.json") }

    func reload() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: Paths.projects, includingPropertiesForKeys: nil)) ?? []
        var list: [ProjectSummary] = []
        for dir in dirs {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("project.json")), let p = try? Project.decode(data) else { continue }
            list.append(summary(p))
        }
        projects = list.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func summary(_ p: Project) -> ProjectSummary {
        ProjectSummary(id: p.id, name: p.name, updatedAt: p.updatedAt, icon: p.brand.icon, theme: p.theme, screenCount: p.screens.count, templateID: p.templateID)
    }

    func load(_ id: UUID) -> Project? {
        guard let data = try? Data(contentsOf: file(for: id)) else { return nil }
        return try? Project.decode(data)
    }

    func save(_ p: Project) {
        do {
            try FileManager.default.createDirectory(at: folder(for: p.id), withIntermediateDirectories: true)
            try p.jsonData(pretty: true).write(to: file(for: p.id), options: .atomic)
            if let i = projects.firstIndex(where: { $0.id == p.id }) { projects[i] = summary(p) } else { projects.insert(summary(p), at: 0) }
            projects.sort { $0.updatedAt > $1.updatedAt }
        } catch {
            message = "Couldn't save \(p.name): \(error.localizedDescription)"
        }
    }

    @discardableResult
    func create(from template: AppTemplate?, name: String) -> Project {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = (template ?? Templates.template("blank")!).makeProject(named: clean.isEmpty ? (template?.name ?? "My App") : clean)
        save(p)
        return p
    }

    func open(_ id: UUID) {
        if let p = load(id) { openProject = p } else { message = "This project could not be opened." }
    }

    @discardableResult
    func duplicate(_ id: UUID) -> Project? {
        guard var p = load(id) else { return nil }
        let old = p.id
        p.id = UUID()
        p.name = uniqueName(p.name + " Copy")
        p.brand.displayName = p.name
        p.bundleID = BundleID.suggest(for: p.name)
        p.createdAt = Date(); p.updatedAt = Date()
        save(p)
        let src = folder(for: old).appendingPathComponent("assets")
        if FileManager.default.fileExists(atPath: src.path) {
            try? FileManager.default.removeItem(at: assetsFolder(for: p.id))
            try? FileManager.default.copyItem(at: src, to: assetsFolder(for: p.id))
        }
        return p
    }

    func rename(_ id: UUID, to name: String) {
        guard var p = load(id), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        p.name = name
        p.brand.displayName = name
        p.touch()
        save(p)
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(for: id))
        projects.removeAll { $0.id == id }
    }

    func uniqueName(_ base: String) -> String {
        var name = base, n = 2
        while projects.contains(where: { $0.name == name }) { name = "\(base) \(n)"; n += 1 }
        return name
    }

    // MARK: Assets

    /// Saves an imported image; returns its asset id (referenced as "asset:<id>").
    func storeAsset(_ data: Data, projectID: UUID, ext: String = "jpg") -> String {
        let id = IDGen.short("img") + "." + ext
        try? data.write(to: assetsFolder(for: projectID).appendingPathComponent(id))
        return id
    }

    func assets(for projectID: UUID) -> [String: Data] {
        let dir = assetsFolder(for: projectID)
        var out: [String: Data] = [:]
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
            if let d = try? Data(contentsOf: f) { out[f.lastPathComponent] = d }
        }
        return out
    }

    // MARK: Import / export

    /// Exports a .reyforge archive (project.json + assets) to a temporary file.
    func exportArchive(_ id: UUID) throws -> URL {
        guard let p = load(id) else { throw ZipError("Project not found") }
        let url = Paths.scratch("export").appendingPathComponent(AppAssembler.safeAppName(p.name) + ".reyforge")
        let w = try ZipWriter(url: url)
        try w.addData("project.json", try p.jsonData(pretty: true))
        for (name, data) in assets(for: id) { try w.addData("assets/\(name)", data, compress: false) }
        try w.finish()
        return url
    }

    /// Imports .reyforge archives, ReyForge project JSON and ReyForge 2.x exports.
    @discardableResult
    func importFile(_ url: URL) throws -> Project {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var assets: [String: Data] = [:]
        var projectData: Data?
        let head = (try? FileHandle(forReadingFrom: url).readData(ofLength: 2)) ?? Data()
        if head == Data([0x50, 0x4B]) {
            let zip = try ZipReader(url: url)
            for e in zip.entries where !e.isDirectory {
                if e.name.hasSuffix("project.json") { projectData = try zip.data(e) }
                else if e.name.hasPrefix("assets/") { assets[String(e.name.dropFirst(7))] = try zip.data(e) }
            }
        } else {
            projectData = try Data(contentsOf: url)
        }
        guard let data = projectData else { throw ZipError("No project.json found in \(url.lastPathComponent)") }
        var project: Project
        if let p = try? Project.decode(data), !p.screens.isEmpty {
            project = p
        } else if let legacy = LegacyMigration.migrate(data: data).first {
            project = legacy
        } else {
            throw ZipError("\(url.lastPathComponent) is not a ReyForge project")
        }
        if projects.contains(where: { $0.id == project.id }) { project.id = UUID() }
        project.name = uniqueName(project.name)
        project.touch()
        save(project)
        for (name, d) in assets { try? d.write(to: assetsFolder(for: project.id).appendingPathComponent(name)) }
        return project
    }

    func handleOpen(_ url: URL) {
        guard url.isFileURL else { return }
        do {
            let p = try importFile(url)
            message = "Imported \(p.name)"
            openProject = p
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: ReyForge 2.x

    private func migrateLegacyIfNeeded() {
        let d = UserDefaults.standard
        guard !Paths.isUITest, !d.bool(forKey: "reyforge.migrated.v3"), let data = d.data(forKey: LegacyMigration.legacyDefaultsKey) else { return }
        for p in LegacyMigration.migrate(data: data) { save(p) }
        d.set(true, forKey: "reyforge.migrated.v3")
    }
}
