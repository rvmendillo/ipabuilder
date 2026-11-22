import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct GitHubRelease: Decodable, Hashable {
    public struct Asset: Decodable, Hashable {
        public let id: Int
        public let name: String
        public let size: Int
        public let browser_download_url: String
        public let url: String
    }
    public let id: Int
    public let tag_name: String
    public let name: String?
    public let body: String?
    public let html_url: String
    public let published_at: String?
    public let prerelease: Bool?
    public let assets: [Asset]

    /// Prefers the "lite" IPA (the model already lives in the app container) unless asked otherwise.
    public func ipaAsset(preferLite: Bool = true, signed: Bool = false) -> Asset? {
        let ipas = assets.filter { $0.name.lowercased().hasSuffix(".ipa") && ($0.name.lowercased().contains("signed") == signed || !signed && !$0.name.lowercased().contains("-signed")) }
        let lite = ipas.first { $0.name.lowercased().contains("lite") }
        let full = ipas.first { !$0.name.lowercased().contains("lite") }
        return preferLite ? (lite ?? full) : (full ?? lite)
    }

    public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
}

public struct GitHubWorkflowRun: Decodable, Hashable {
    public let id: Int
    public let status: String
    public let conclusion: String?
    public let html_url: String
    public let display_title: String?
    public let head_sha: String?
    public let created_at: String?
}

public struct GitHubArtifact: Decodable, Hashable {
    public let id: Int
    public let name: String
    public let size_in_bytes: Int
    public let expired: Bool
    public let archive_download_url: String
}

/// Compares dotted versions ("3.0.12" vs "3.0.9").
public enum SemVer {
    public static func compare(_ a: String, _ b: String) -> Int {
        let pa = a.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        let pb = b.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
    public static func isNewer(_ candidate: String, than current: String) -> Bool { compare(candidate, current) > 0 }
}

public struct GitHubError: LocalizedError, CustomStringConvertible {
    public let status: Int
    public let message: String
    public var description: String { "GitHub \(status): \(message)" }
    public var errorDescription: String? {
        switch status {
        case 401: return "GitHub rejected the token. Create a fine-grained token with Contents and Actions access."
        case 403: return "GitHub denied access (\(message)). Check the token's repository permissions or rate limit."
        case 404: return "Not found on GitHub. Check the owner/repository name and that the token can see it."
        default: return description
        }
    }
}

/// Minimal GitHub REST client for releases (self-update) and Actions (cloud builds).
public final class GitHubClient {
    public var owner: String
    public var repo: String
    public var token: String?
    let session: URLSession
    public var apiBase = URL(string: "https://api.github.com")!

    public init(owner: String, repo: String, token: String? = nil, session: URLSession = .shared) {
        self.owner = owner; self.repo = repo; self.token = token; self.session = session
    }

    public func request(_ path: String, method: String = "GET", body: Any? = nil, accept: String = "application/vnd.github+json") throws -> URLRequest {
        guard let url = URL(string: apiBase.absoluteString + path) else { throw GitHubError(status: 0, message: "Invalid URL") }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.timeoutInterval = 60
        r.setValue(accept, forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("ReyForge", forHTTPHeaderField: "User-Agent")
        if let t = token, !t.isEmpty { r.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        if let b = body {
            r.httpBody = try JSONSerialization.data(withJSONObject: b)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    var repoPath: String { "/repos/\(owner)/\(repo)" }

    func send(_ r: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw GitHubError(status: status, message: msg)
        }
        return data
    }

    // MARK: Releases

    public func latestRelease() async throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: try await send(request("\(repoPath)/releases/latest")))
    }

    public func releases(perPage: Int = 10) async throws -> [GitHubRelease] {
        try JSONDecoder().decode([GitHubRelease].self, from: try await send(request("\(repoPath)/releases?per_page=\(perPage)")))
    }

    /// Downloads a release asset to a file (works for public repos without a token).
    public func download(asset: GitHubRelease.Asset, to destination: URL, progress: ((Double) -> Void)? = nil) async throws {
        var r = try request("\(repoPath)/releases/assets/\(asset.id)", accept: "application/octet-stream")
        if token == nil || token?.isEmpty == true, let u = URL(string: asset.browser_download_url) { r = URLRequest(url: u) }
        try await GitHubClient.downloadFile(r, to: destination, session: session, expectedSize: Int64(asset.size), progress: progress)
    }

    public static func downloadFile(_ r: URLRequest, to destination: URL, session: URLSession, expectedSize: Int64, progress: ((Double) -> Void)?) async throws {
        let (tmp, response) = try await session.download(for: r)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else { throw GitHubError(status: status, message: "Download failed") }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tmp, to: destination)
        progress?(1)
    }

    // MARK: Contents (job upload)

    public func putFile(path: String, content: Data, message: String, branch: String? = nil, sha: String? = nil) async throws -> String? {
        var body: [String: Any] = ["message": message, "content": content.base64EncodedString()]
        if let b = branch { body["branch"] = b }
        if let s = sha { body["sha"] = s }
        let data = try await send(request("\(repoPath)/contents/\(path)", method: "PUT", body: body))
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (obj?["commit"] as? [String: Any])?["sha"] as? String
    }

    public func fileSHA(path: String, ref: String? = nil) async throws -> String? {
        let q = ref.map { "?ref=\($0)" } ?? ""
        guard let data = try? await send(request("\(repoPath)/contents/\(path)\(q)")) else { return nil }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["sha"] as? String
    }

    public func deleteFile(path: String, message: String, branch: String? = nil) async throws {
        guard let sha = try await fileSHA(path: path, ref: branch) else { return }
        var body: [String: Any] = ["message": message, "sha": sha]
        if let b = branch { body["branch"] = b }
        _ = try await send(request("\(repoPath)/contents/\(path)", method: "DELETE", body: body))
    }

    // MARK: Actions

    public func dispatch(workflow: String, ref: String, inputs: [String: String]) async throws {
        _ = try await send(request("\(repoPath)/actions/workflows/\(workflow)/dispatches", method: "POST", body: ["ref": ref, "inputs": inputs]))
    }

    public func runs(workflow: String, event: String = "workflow_dispatch", perPage: Int = 10) async throws -> [GitHubWorkflowRun] {
        let data = try await send(request("\(repoPath)/actions/workflows/\(workflow)/runs?event=\(event)&per_page=\(perPage)"))
        struct Envelope: Decodable { let workflow_runs: [GitHubWorkflowRun] }
        return try JSONDecoder().decode(Envelope.self, from: data).workflow_runs
    }

    public func run(id: Int) async throws -> GitHubWorkflowRun {
        try JSONDecoder().decode(GitHubWorkflowRun.self, from: try await send(request("\(repoPath)/actions/runs/\(id)")))
    }

    public func artifacts(runID: Int) async throws -> [GitHubArtifact] {
        struct Envelope: Decodable { let artifacts: [GitHubArtifact] }
        return try JSONDecoder().decode(Envelope.self, from: try await send(request("\(repoPath)/actions/runs/\(runID)/artifacts"))).artifacts
    }

    public func download(artifact: GitHubArtifact, to destination: URL) async throws {
        let r = try request("\(repoPath)/actions/artifacts/\(artifact.id)/zip")
        try await GitHubClient.downloadFile(r, to: destination, session: session, expectedSize: Int64(artifact.size_in_bytes), progress: nil)
    }
}
