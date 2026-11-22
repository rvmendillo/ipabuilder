import Foundation

/// Pure HTTP/1.1 logic for the on-device localhost installer (the socket layer lives in the app).
public enum MiniHTTP {
    public struct Request: Hashable {
        public var method: String
        public var path: String
        public var query: [String: String]
        public var headers: [String: String]
    }

    public enum ParseResult: Equatable { case incomplete, tooLarge, malformed, request(Request) }

    public static let maxHeaderBytes = 16 * 1024

    public static func parse(_ data: Data) -> ParseResult {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderBytes ? .tooLarge : .incomplete
        }
        guard end.lowerBound <= maxHeaderBytes, let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return .tooLarge }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines[0].split(separator: " ")
        guard parts.count >= 2 else { return .malformed }
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[..<c].trimmingCharacters(in: .whitespaces).lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        var target = String(parts[1])
        var query: [String: String] = [:]
        if let q = target.firstIndex(of: "?") {
            for pair in target[target.index(after: q)...].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                query[kv[0].removingPercentEncoding ?? kv[0]] = kv.count > 1 ? (kv[1].removingPercentEncoding ?? kv[1]) : ""
            }
            target = String(target[..<q])
        }
        return .request(Request(method: String(parts[0]).uppercased(), path: target.removingPercentEncoding ?? target, query: query, headers: headers))
    }

    public enum RangeResult: Equatable { case full, partial(start: UInt64, end: UInt64), unsatisfiable }

    /// Resolves a `Range: bytes=…` header for a file of `size` bytes (single ranges only, as installers use).
    public static func range(_ header: String?, size: UInt64) -> RangeResult {
        guard let h = header?.trimmingCharacters(in: .whitespaces), h.lowercased().hasPrefix("bytes=") else { return .full }
        let spec = h.dropFirst(6).split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let bounds = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard bounds.count == 2, size > 0 else { return size == 0 ? .full : .unsatisfiable }
        if bounds[0].isEmpty {
            guard let suffix = UInt64(bounds[1]), suffix > 0 else { return .unsatisfiable }
            return .partial(start: size - min(suffix, size), end: size - 1)
        }
        guard let start = UInt64(bounds[0]), start < size else { return .unsatisfiable }
        let end = bounds[1].isEmpty ? size - 1 : min(UInt64(bounds[1]) ?? (size - 1), size - 1)
        guard end >= start else { return .unsatisfiable }
        return .partial(start: start, end: end)
    }

    public static func responseHead(status: Int, reason: String, headers: [(String, String)]) -> Data {
        var s = "HTTP/1.1 \(status) \(reason)\r\n"
        for (k, v) in headers { s += "\(k): \(v)\r\n" }
        s += "\r\n"
        return Data(s.utf8)
    }

    public static func simple(_ status: Int, _ reason: String, body: String = "", contentType: String = "text/plain; charset=utf-8") -> Data {
        let b = Data(body.utf8)
        return responseHead(status: status, reason: reason, headers: [("Content-Type", contentType), ("Content-Length", String(b.count)), ("Cache-Control", "no-store"), ("Connection", "close")]) + b
    }

    /// Headers for serving a file (full or ranged).
    public static func fileHead(range: RangeResult, size: UInt64, contentType: String) -> (Data, UInt64, UInt64)? {
        switch range {
        case .full:
            return (responseHead(status: 200, reason: "OK", headers: [("Content-Type", contentType), ("Content-Length", String(size)), ("Accept-Ranges", "bytes"), ("Cache-Control", "no-store"), ("Connection", "close")]), 0, size)
        case .partial(let s, let e):
            let len = e - s + 1
            return (responseHead(status: 206, reason: "Partial Content", headers: [("Content-Type", contentType), ("Content-Length", String(len)), ("Content-Range", "bytes \(s)-\(e)/\(size)"), ("Accept-Ranges", "bytes"), ("Cache-Control", "no-store"), ("Connection", "close")]), s, len)
        case .unsatisfiable:
            return nil
        }
    }
}

/// Builds the links iOS needs to install an IPA over the air.
public enum InstallLinks {
    /// The manifest helper ReyForge 2.x used; returns an HTTPS manifest that points at our localhost IPA.
    public static let defaultManifestHelper = "https://api.palera.in/genPlist"

    static let queryAllowed: CharacterSet = {
        var c = CharacterSet.alphanumerics
        c.insert(charactersIn: "-._~")
        return c
    }()

    public static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? s }

    public static func manifestURL(helper: String = defaultManifestHelper, bundleID: String, name: String, version: String, ipaURL: String) -> URL? {
        URL(string: "\(helper)?bundleid=\(encode(bundleID))&name=\(encode(name))&version=\(encode(version))&fetchurl=\(encode(ipaURL))")
    }

    public static func itmsServices(manifest: URL) -> URL? {
        URL(string: "itms-services://?action=download-manifest&url=\(encode(manifest.absoluteString))")
    }

    /// A manifest you can host yourself (e.g. on GitHub Pages) instead of using a helper.
    public static func manifestPlist(bundleID: String, name: String, version: String, ipaURL: String, iconURL: String? = nil) -> Data {
        var assets: [[String: Any]] = [["kind": "software-package", "url": ipaURL]]
        if let icon = iconURL {
            assets.append(["kind": "display-image", "url": icon])
            assets.append(["kind": "full-size-image", "url": icon])
        }
        let manifest: [String: Any] = ["items": [["assets": assets, "metadata": ["bundle-identifier": bundleID, "bundle-version": version, "kind": "software", "title": name]]]]
        return (try? PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)) ?? Data()
    }

    public static func installPage(appName: String, itmsURL: String) -> String {
        """
        <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Install \(appName)</title></head>
        <body style="background:#0E0B1F;color:#fff;font:17px -apple-system,system-ui;padding:28px;text-align:center">
        <h1 style="font-weight:700">Install \(appName)</h1>
        <p style="color:#B9B4D9">Tap the button, then confirm the prompt. Keep ReyForge open until the download finishes.</p>
        <p><a style="display:inline-block;background:linear-gradient(135deg,#6C5CFF,#FF7A45);color:#fff;padding:14px 28px;border-radius:14px;text-decoration:none;font-weight:600" href="\(itmsURL)">Install</a></p>
        <script>setTimeout(function(){window.location="\(itmsURL)";},250);</script>
        </body></html>
        """
    }
}
