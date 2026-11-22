import ReyForgeCore
import Foundation
// Writes a sample IPA-shaped archive for external validation.
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let src = out.deletingLastPathComponent().appendingPathComponent("zipsrc/Payload/Demo.app")
try? FileManager.default.removeItem(at: src.deletingLastPathComponent().deletingLastPathComponent())
try FileManager.default.createDirectory(at: src.appendingPathComponent("Frameworks"), withIntermediateDirectories: true)
try Data(repeating: 7, count: 2_000_000).write(to: src.appendingPathComponent("Frameworks/big.bin"))
try Data("hello".utf8).write(to: src.appendingPathComponent("Demo"))
try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o755)], ofItemAtPath: src.appendingPathComponent("Demo").path)
let w = try ZipWriter(url: out)
try w.addDirectoryContents(of: src.deletingLastPathComponent(), prefix: "Payload")
try w.finish()
print("wrote", out.path)
