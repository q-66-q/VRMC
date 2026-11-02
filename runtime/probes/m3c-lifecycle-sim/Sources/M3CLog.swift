import Foundation

/// Single-process log used by the probe: writes Documents/sim-shell.log and NSLog (so the line also
/// appears in the simulator system log). Thread safe because the render thread logs too.
enum M3CLog {
    private static let lock = NSLock()
    private static let startTime = CFAbsoluteTimeGetCurrent()
    private static let url: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("sim-shell.log")
    }()

    static func line(_ tag: String, _ message: String) {
        let elapsed = String(format: "%.3f", CFAbsoluteTimeGetCurrent() - startTime)
        let text = "[\(tag) t=+\(elapsed)] \(message)\n"
        lock.lock()
        NSLog("M3C %@", text)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
        lock.unlock()
    }

    static func shell(_ message: String) { line("shell", message) }
    static func comp(_ message: String) { line("comp", message) }
}
