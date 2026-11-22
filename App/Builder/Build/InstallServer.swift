import Foundation
import Network
import UIKit
import ReyForgeCore

/// A tiny localhost HTTP server that hands a signed IPA to the iOS installer (itms-services).
final class InstallServer {
    static let shared = InstallServer()

    private let queue = DispatchQueue(label: "com.reyforge.install-server")
    private var listener: NWListener?
    private var files: [String: URL] = [:]
    private(set) var port: UInt16 = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    var onRequest: ((String) -> Void)?

    /// Starts (or reuses) the server and publishes `file` at `path`. Returns the local URL.
    func serve(_ file: URL, at path: String = "/app.ipa") async throws -> URL {
        queue.sync { files[path] = file }
        if listener == nil || port == 0 { try await start() }
        return URL(string: "http://127.0.0.1:\(port)\(path)")!
    }

    private func start() async throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        params.allowLocalEndpointReuse = true
        let l = try NWListener(using: params)
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        port = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            l.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !resumed { resumed = true; cont.resume(returning: l.port?.rawValue ?? 0) }
                case .failed(let e):
                    if !resumed { resumed = true; cont.resume(throwing: e) }
                case .cancelled:
                    if !resumed { resumed = true; cont.resume(throwing: VaultError("The install server stopped.")) }
                default: break
                }
            }
            l.start(queue: queue)
        }
        listener = l
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = 0
        queue.sync { files.removeAll() }
        Task { @MainActor in self.endBackgroundTask() }
    }

    /// Keeps the server alive briefly after iOS switches to the install prompt.
    @MainActor func keepAliveInBackground() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "ReyForge install") { [weak self] in
            Task { @MainActor in self?.endBackgroundTask() }
        }
    }

    @MainActor private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    // MARK: Connections

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receiveHeaders(conn, buffer: Data())
    }

    private func receiveHeaders(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, complete, error in
            guard let self = self else { conn.cancel(); return }
            var buf = buffer
            if let d = data { buf.append(d) }
            switch MiniHTTP.parse(buf) {
            case .incomplete:
                if complete || error != nil { conn.cancel() } else { self.receiveHeaders(conn, buffer: buf) }
            case .tooLarge, .malformed:
                self.send(conn, MiniHTTP.simple(400, "Bad Request"))
            case .request(let req):
                self.handle(req, conn)
            }
        }
    }

    private func handle(_ req: MiniHTTP.Request, _ conn: NWConnection) {
        onRequest?("\(req.method) \(req.path)")
        guard req.method == "GET" || req.method == "HEAD" else { send(conn, MiniHTTP.simple(405, "Method Not Allowed")); return }
        if req.path == "/ping" { send(conn, MiniHTTP.simple(200, "OK", body: "ReyForge")); return }
        guard let file = files[req.path], let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value else {
            send(conn, MiniHTTP.simple(404, "Not Found")); return
        }
        let type = file.pathExtension == "plist" ? "text/xml" : (file.pathExtension == "png" ? "image/png" : "application/octet-stream")
        guard let (head, start, length) = MiniHTTP.fileHead(range: MiniHTTP.range(req.headers["range"], size: size), size: size, contentType: type) else {
            send(conn, MiniHTTP.responseHead(status: 416, reason: "Range Not Satisfiable", headers: [("Content-Range", "bytes */\(size)"), ("Connection", "close")]))
            return
        }
        conn.send(content: head, completion: .contentProcessed { [weak self] error in
            guard error == nil, req.method == "GET", let self = self, let handle = try? FileHandle(forReadingFrom: file) else { conn.cancel(); return }
            handle.seek(toFileOffset: start)
            self.stream(handle, remaining: length, conn)
        })
    }

    private func stream(_ handle: FileHandle, remaining: UInt64, _ conn: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            conn.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
            return
        }
        let chunk = handle.readData(ofLength: Int(min(remaining, 512 * 1024)))
        guard !chunk.isEmpty else { try? handle.close(); conn.cancel(); return }
        conn.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard error == nil, let self = self else { try? handle.close(); conn.cancel(); return }
            self.stream(handle, remaining: remaining - UInt64(chunk.count), conn)
        })
    }

    private func send(_ conn: NWConnection, _ data: Data) {
        conn.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in conn.cancel() })
    }
}

/// Installs an IPA on this device through the system installer.
enum DeviceInstaller {
    @MainActor
    static func install(ipa: URL, bundleID: String, name: String, version: String) async throws {
        let local = try await InstallServer.shared.serve(ipa)
        guard let manifest = InstallLinks.manifestURL(bundleID: bundleID, name: name, version: version, ipaURL: local.absoluteString),
              let itms = InstallLinks.itmsServices(manifest: manifest) else {
            throw VaultError("Couldn't create the install link.")
        }
        InstallServer.shared.keepAliveInBackground()
        let opened = await UIApplication.shared.open(itms)
        if !opened { throw VaultError("iOS didn't open the installer. Make sure the IPA is signed with a certificate trusted on this device.") }
    }
}
