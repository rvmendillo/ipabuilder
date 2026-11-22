import Foundation
#if canImport(Compression)
import Compression
#endif

// MARK: - CRC32 (slicing-by-8)

public struct CRC32 {
    static let tables: [[UInt32]] = {
        var t = [[UInt32]](repeating: [UInt32](repeating: 0, count: 256), count: 8)
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1) }
            t[0][i] = c
        }
        for i in 0..<256 {
            for k in 1..<8 { t[k][i] = (t[k - 1][i] >> 8) ^ t[0][Int(t[k - 1][i] & 0xFF)] }
        }
        return t
    }()

    public private(set) var value: UInt32 = 0xFFFFFFFF
    public init() {}

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            update(base, count: raw.count)
        }
    }

    public mutating func update(_ p: UnsafePointer<UInt8>, count n: Int) {
        let t = CRC32.tables
        var c = value
        var i = 0
        while i + 8 <= n {
            c ^= UInt32(p[i]) | UInt32(p[i + 1]) << 8 | UInt32(p[i + 2]) << 16 | UInt32(p[i + 3]) << 24
            let hi = UInt32(p[i + 4]) | UInt32(p[i + 5]) << 8 | UInt32(p[i + 6]) << 16 | UInt32(p[i + 7]) << 24
            c = t[7][Int(c & 0xFF)] ^ t[6][Int((c >> 8) & 0xFF)] ^ t[5][Int((c >> 16) & 0xFF)] ^ t[4][Int(c >> 24)]
              ^ t[3][Int(hi & 0xFF)] ^ t[2][Int((hi >> 8) & 0xFF)] ^ t[1][Int((hi >> 16) & 0xFF)] ^ t[0][Int(hi >> 24)]
            i += 8
        }
        while i < n { c = t[0][Int((c ^ UInt32(p[i])) & 0xFF)] ^ (c >> 8); i += 1 }
        value = c
    }

    public var checksum: UInt32 { value ^ 0xFFFFFFFF }

    public static func checksum(_ data: Data) -> UInt32 { var c = CRC32(); c.update(data); return c.checksum }
}

public struct ZipError: LocalizedError, CustomStringConvertible {
    public let message: String
    public init(_ m: String) { message = m }
    public var description: String { message }
    public var errorDescription: String? { message }
}

// MARK: - Streaming raw DEFLATE (Apple Compression framework)

#if canImport(Compression)
final class DeflateStream {
    /// Owned C struct; `compression_stream_init` fills every field.
    private let stream: UnsafeMutablePointer<compression_stream>
    private let bufferSize = 256 * 1024
    private let buffer: UnsafeMutablePointer<UInt8>
    private let encode: Bool
    private let emptyInput = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)

    init(encode: Bool) throws {
        self.encode = encode
        buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        let status = compression_stream_init(stream, encode ? COMPRESSION_STREAM_ENCODE : COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB)
        guard status == COMPRESSION_STATUS_OK else {
            buffer.deallocate(); stream.deallocate(); emptyInput.deallocate()
            throw ZipError("Could not start compression")
        }
    }

    deinit {
        _ = compression_stream_destroy(stream)
        stream.deallocate()
        buffer.deallocate()
        emptyInput.deallocate()
    }

    /// Feeds input and emits produced output. Pass `final` on the last call.
    func process(_ input: Data, final: Bool, emit: (Data) throws -> Void) throws {
        try input.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let src = raw.bindMemory(to: UInt8.self)
            stream.pointee.src_ptr = src.baseAddress ?? UnsafePointer(emptyInput)
            stream.pointee.src_size = src.count
            var stalls = 0
            while true {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                let before = stream.pointee.src_size
                let status = compression_stream_process(stream, final ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                let produced = bufferSize - stream.pointee.dst_size
                if produced > 0 { try emit(Data(bytes: buffer, count: produced)) }
                if status == COMPRESSION_STATUS_END { return }
                guard status == COMPRESSION_STATUS_OK else { throw ZipError(encode ? "Compression failed" : "This ZIP entry is corrupted") }
                if stream.pointee.src_size == 0 && produced < bufferSize && !final { return }
                // Guard against truncated input when finalizing a decode.
                if produced == 0 && stream.pointee.src_size == before {
                    stalls += 1
                    if stalls > 3 { if encode { throw ZipError("Compression stalled") } else { return } }
                } else { stalls = 0 }
            }
        }
    }
}
#endif

public enum ZipSupport {
    /// Raw DEFLATE is available on Apple platforms; elsewhere archives are written uncompressed.
    public static var canDeflate: Bool {
        #if canImport(Compression)
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Writer

public final class ZipWriter {
    struct Entry { var name: String; var crc: UInt32; var compressed: UInt64; var size: UInt64; var method: UInt16; var offset: UInt64; var dosTime: UInt16; var dosDate: UInt16; var mode: UInt32; var isDirectory: Bool }

    let handle: FileHandle
    var offset: UInt64 = 0
    var entries: [Entry] = []
    let (dosTime, dosDate): (UInt16, UInt16)
    public var compressionThreshold: UInt64 = 48 * 1024 * 1024

    public init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let h = FileHandle(forWritingAtPath: url.path) else { throw ZipError("Cannot write \(url.lastPathComponent)") }
        handle = h
        let c = Calendar(identifier: .gregorian).dateComponents(in: TimeZone.current, from: Date())
        dosTime = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | ((c.second ?? 0) / 2))
        dosDate = UInt16(max(0, (c.year ?? 1980) - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
    }

    func write(_ d: Data) { handle.write(d); offset += UInt64(d.count) }

    static func le16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
    static func le32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }

    func localHeader(_ e: Entry, nameData: Data) -> Data {
        var d = Data()
        d += ZipWriter.le32(0x04034b50)
        d += ZipWriter.le16(20)
        // UTF-8 names. No data descriptor: CRC and sizes are back-patched into this header so
        // streaming unzippers (like the iOS installer) can read stored entries.
        d += ZipWriter.le16(0x0800)
        d += ZipWriter.le16(e.method)
        d += ZipWriter.le16(e.dosTime); d += ZipWriter.le16(e.dosDate)
        d += ZipWriter.le32(0); d += ZipWriter.le32(0); d += ZipWriter.le32(0)
        d += ZipWriter.le16(UInt16(nameData.count)); d += ZipWriter.le16(0)
        d += nameData
        return d
    }

    public func addDirectory(_ path: String, mode: UInt32 = 0o755) {
        let name = path.hasSuffix("/") ? path : path + "/"
        let nameData = Data(name.utf8)
        let e = Entry(name: name, crc: 0, compressed: 0, size: 0, method: 0, offset: offset, dosTime: dosTime, dosDate: dosDate, mode: mode, isDirectory: true)
        write(localHeader(e, nameData: nameData))
        entries.append(e)
    }

    public func addData(_ path: String, _ data: Data, mode: UInt32 = 0o644, compress: Bool = true) throws {
        try addStream(path, size: UInt64(data.count), mode: mode, compress: compress) { emit in try emit(data) }
    }

    public func addFile(_ path: String, from url: URL, compress: Bool = true) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let mode = (attrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0o644
        guard let h = FileHandle(forReadingAtPath: url.path) else { throw ZipError("Cannot read \(url.lastPathComponent)") }
        defer { h.closeFile() }
        try addStream(path, size: size, mode: mode, compress: compress && size < compressionThreshold) { emit in
            while true {
                let chunk = h.readData(ofLength: 1 << 20)
                if chunk.isEmpty { break }
                try emit(chunk)
            }
        }
    }

    func addStream(_ path: String, size: UInt64, mode: UInt32, compress: Bool, produce: ((Data) throws -> Void) throws -> Void) throws {
        guard size < 0xFFFF_FFFF else { throw ZipError("\(path) is larger than 4 GB") }
        let useDeflate = compress && ZipSupport.canDeflate && size > 64
        let nameData = Data(path.utf8)
        var e = Entry(name: path, crc: 0, compressed: 0, size: size, method: useDeflate ? 8 : 0, offset: offset, dosTime: dosTime, dosDate: dosDate, mode: mode, isDirectory: false)
        write(localHeader(e, nameData: nameData))
        var crc = CRC32()
        var written: UInt64 = 0
        #if canImport(Compression)
        if useDeflate {
            let deflater = try DeflateStream(encode: true)
            try produce { chunk in
                crc.update(chunk)
                try deflater.process(chunk, final: false) { out in self.write(out); written += UInt64(out.count) }
            }
            try deflater.process(Data(), final: true) { out in self.write(out); written += UInt64(out.count) }
        } else {
            try produce { chunk in crc.update(chunk); self.write(chunk); written += UInt64(chunk.count) }
        }
        #else
        try produce { chunk in crc.update(chunk); self.write(chunk); written += UInt64(chunk.count) }
        #endif
        e.crc = crc.checksum
        e.compressed = written
        guard e.compressed < 0xFFFF_FFFF else { throw ZipError("\(path) is larger than 4 GB") }
        // Back-patch CRC and sizes into the local header.
        handle.seek(toFileOffset: e.offset + 14)
        handle.write(ZipWriter.le32(e.crc) + ZipWriter.le32(UInt32(e.compressed)) + ZipWriter.le32(UInt32(e.size)))
        handle.seek(toFileOffset: offset)
        entries.append(e)
    }

    /// Recursively adds a directory's contents under `prefix` (e.g. "Payload/App.app").
    public func addDirectoryContents(of dir: URL, prefix: String, compress: Bool = true) throws {
        let fm = FileManager.default
        addDirectory(prefix)
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let name = prefix + "/" + item.lastPathComponent
            if values.isSymbolicLink == true {
                let dest = try fm.destinationOfSymbolicLink(atPath: item.path)
                try addData(name, Data(dest.utf8), mode: 0o120755, compress: false)
            } else if values.isDirectory == true {
                try addDirectoryContents(of: item, prefix: name, compress: compress)
            } else {
                try addFile(name, from: item, compress: compress)
            }
        }
    }

    public func finish() throws {
        let cdStart = offset
        for e in entries {
            let nameData = Data(e.name.utf8)
            var d = Data()
            d += ZipWriter.le32(0x02014b50)
            d += ZipWriter.le16(0x031E)          // made by UNIX, spec 3.0
            d += ZipWriter.le16(20)
            d += ZipWriter.le16(0x0800)
            d += ZipWriter.le16(e.method)
            d += ZipWriter.le16(e.dosTime); d += ZipWriter.le16(e.dosDate)
            d += ZipWriter.le32(e.crc); d += ZipWriter.le32(UInt32(e.compressed)); d += ZipWriter.le32(UInt32(e.size))
            d += ZipWriter.le16(UInt16(nameData.count)); d += ZipWriter.le16(0); d += ZipWriter.le16(0)
            d += ZipWriter.le16(0); d += ZipWriter.le16(0)
            let type: UInt32 = e.isDirectory ? 0o040000 : (e.mode & 0o170000 == 0 ? 0o100000 : 0)
            d += ZipWriter.le32(((type | e.mode) << 16) | (e.isDirectory ? 0x10 : 0))
            d += ZipWriter.le32(UInt32(e.offset))
            d += nameData
            write(d)
        }
        let cdSize = offset - cdStart
        guard entries.count < 0xFFFF, cdStart < 0xFFFF_FFFF else { throw ZipError("Archive too large") }
        var end = Data()
        end += ZipWriter.le32(0x06054b50)
        end += ZipWriter.le16(0); end += ZipWriter.le16(0)
        end += ZipWriter.le16(UInt16(entries.count)); end += ZipWriter.le16(UInt16(entries.count))
        end += ZipWriter.le32(UInt32(cdSize)); end += ZipWriter.le32(UInt32(cdStart))
        end += ZipWriter.le16(0)
        write(end)
        handle.closeFile()
    }

    /// Zips a folder (e.g. one containing "Payload/") into `url`.
    public static func zipDirectory(_ dir: URL, to url: URL, compress: Bool = true) throws {
        let w = try ZipWriter(url: url)
        let fm = FileManager.default
        for item in try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if (try item.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                try w.addDirectoryContents(of: item, prefix: item.lastPathComponent, compress: compress)
            } else {
                try w.addFile(item.lastPathComponent, from: item, compress: compress)
            }
        }
        try w.finish()
    }
}

// MARK: - Reader

public final class ZipReader {
    public struct Entry {
        public var name: String
        public var method: UInt16
        public var crc: UInt32
        public var compressedSize: UInt64
        public var size: UInt64
        public var localHeaderOffset: UInt64
        public var externalAttributes: UInt32
        public var isDirectory: Bool { name.hasSuffix("/") }
        public var unixMode: UInt32 { externalAttributes >> 16 }
        public var isSymlink: Bool { unixMode & 0o170000 == 0o120000 }
    }

    let handle: FileHandle
    public private(set) var entries: [Entry] = []

    public init(url: URL) throws {
        guard let h = FileHandle(forReadingAtPath: url.path) else { throw ZipError("Cannot open \(url.lastPathComponent)") }
        handle = h
        try readCentralDirectory()
    }

    deinit { handle.closeFile() }

    func read(at offset: UInt64, _ count: Int) -> Data {
        handle.seek(toFileOffset: offset)
        return handle.readData(ofLength: count)
    }

    static func u16(_ d: Data, _ o: Int) -> UInt16 { UInt16(d[d.startIndex + o]) | UInt16(d[d.startIndex + o + 1]) << 8 }
    static func u32(_ d: Data, _ o: Int) -> UInt32 { UInt32(u16(d, o)) | UInt32(u16(d, o + 2)) << 16 }
    static func u64(_ d: Data, _ o: Int) -> UInt64 { UInt64(u32(d, o)) | UInt64(u32(d, o + 4)) << 32 }

    func readCentralDirectory() throws {
        let size = handle.seekToEndOfFile()
        let tailLen = Int(min(size, 70_000))
        let tail = read(at: size - UInt64(tailLen), tailLen)
        var eocd: Int?
        var i = tail.count - 22
        while i >= 0 {
            if ZipReader.u32(tail, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard let e = eocd else { throw ZipError("Not a ZIP archive") }
        var count = UInt64(ZipReader.u16(tail, e + 10))
        var cdSize = UInt64(ZipReader.u32(tail, e + 12))
        var cdOffset = UInt64(ZipReader.u32(tail, e + 16))
        // ZIP64 end of central directory.
        if cdOffset == 0xFFFF_FFFF || count == 0xFFFF, e >= 20, ZipReader.u32(tail, e - 20) == 0x07064b50 {
            let z64Offset = ZipReader.u64(tail, e - 20 + 8)
            let z = read(at: z64Offset, 56)
            if ZipReader.u32(z, 0) == 0x06064b50 {
                count = ZipReader.u64(z, 32); cdSize = ZipReader.u64(z, 40); cdOffset = ZipReader.u64(z, 48)
            }
        }
        let cd = read(at: cdOffset, Int(cdSize))
        var p = 0
        for _ in 0..<count {
            guard p + 46 <= cd.count, ZipReader.u32(cd, p) == 0x02014b50 else { throw ZipError("Corrupted ZIP directory") }
            let method = ZipReader.u16(cd, p + 10)
            let crc = ZipReader.u32(cd, p + 16)
            var csize = UInt64(ZipReader.u32(cd, p + 20))
            var usize = UInt64(ZipReader.u32(cd, p + 24))
            let nameLen = Int(ZipReader.u16(cd, p + 28))
            let extraLen = Int(ZipReader.u16(cd, p + 30))
            let commentLen = Int(ZipReader.u16(cd, p + 32))
            let ext = ZipReader.u32(cd, p + 38)
            var local = UInt64(ZipReader.u32(cd, p + 42))
            let nameData = cd.subdata(in: (cd.startIndex + p + 46)..<(cd.startIndex + p + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            // ZIP64 extra field.
            var x = p + 46 + nameLen
            let xEnd = x + extraLen
            while x + 4 <= xEnd {
                let id = ZipReader.u16(cd, x), len = Int(ZipReader.u16(cd, x + 2))
                if id == 0x0001 {
                    var q = x + 4
                    if usize == 0xFFFF_FFFF { usize = ZipReader.u64(cd, q); q += 8 }
                    if csize == 0xFFFF_FFFF { csize = ZipReader.u64(cd, q); q += 8 }
                    if local == 0xFFFF_FFFF { local = ZipReader.u64(cd, q) }
                }
                x += 4 + len
            }
            entries.append(Entry(name: name, method: method, crc: crc, compressedSize: csize, size: usize, localHeaderOffset: local, externalAttributes: ext))
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    func dataOffset(_ e: Entry) -> UInt64 {
        let h = read(at: e.localHeaderOffset, 30)
        return e.localHeaderOffset + 30 + UInt64(ZipReader.u16(h, 26)) + UInt64(ZipReader.u16(h, 28))
    }

    /// Streams an entry's uncompressed bytes.
    public func stream(_ e: Entry, _ sink: (Data) throws -> Void) throws {
        var remaining = e.compressedSize
        var pos = dataOffset(e)
        var crc = CRC32()
        switch e.method {
        case 0:
            while remaining > 0 {
                let n = Int(min(remaining, 1 << 20))
                let chunk = read(at: pos, n)
                guard chunk.count == n else { throw ZipError("Unexpected end of \(e.name)") }
                crc.update(chunk); try sink(chunk)
                pos += UInt64(n); remaining -= UInt64(n)
            }
        case 8:
            #if canImport(Compression)
            let inflater = try DeflateStream(encode: false)
            while remaining > 0 {
                let n = Int(min(remaining, 1 << 20))
                let chunk = read(at: pos, n)
                guard chunk.count == n else { throw ZipError("Unexpected end of \(e.name)") }
                pos += UInt64(n); remaining -= UInt64(n)
                try inflater.process(chunk, final: remaining == 0) { out in crc.update(out); try sink(out) }
            }
            #else
            throw ZipError("Compressed ZIP entries are not supported on this platform")
            #endif
        default:
            throw ZipError("Unsupported compression method \(e.method) in \(e.name)")
        }
        if crc.checksum != e.crc && e.size > 0 { throw ZipError("Checksum mismatch in \(e.name)") }
    }

    public func data(_ e: Entry) throws -> Data {
        var out = Data()
        try stream(e) { out.append($0) }
        return out
    }

    public func entry(named name: String) -> Entry? { entries.first { $0.name == name } }

    /// Extracts everything into `dir`, refusing paths that escape it.
    public func extractAll(to dir: URL, progress: ((Double) -> Void)? = nil) throws {
        let fm = FileManager.default
        let root = dir.standardizedFileURL.path
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let total = max(1, entries.reduce(0) { $0 + $1.size })
        var done: UInt64 = 0
        for e in entries {
            if e.name.hasPrefix("__MACOSX/") { continue }
            let dest = dir.appendingPathComponent(e.name).standardizedFileURL
            guard dest.path.hasPrefix(root) else { throw ZipError("Unsafe path in archive: \(e.name)") }
            if e.isDirectory {
                try fm.createDirectory(at: dest, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if e.isSymlink {
                let target = String(decoding: try data(e), as: UTF8.self)
                try? fm.removeItem(at: dest)
                try fm.createSymbolicLink(atPath: dest.path, withDestinationPath: target)
                continue
            }
            fm.createFile(atPath: dest.path, contents: nil)
            guard let out = FileHandle(forWritingAtPath: dest.path) else { throw ZipError("Cannot write \(e.name)") }
            try stream(e) { out.write($0) }
            out.closeFile()
            let mode = e.unixMode & 0o7777
            if mode != 0 { try? fm.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: dest.path) }
            done += e.size
            progress?(Double(done) / Double(total))
        }
    }
}
