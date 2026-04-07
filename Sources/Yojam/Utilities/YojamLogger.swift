import Foundation
import os

final class YojamLogger: @unchecked Sendable {
    static let shared = YojamLogger()
    private let osLog = os.Logger(subsystem: "com.yojam.app", category: "general")
    private let logDir: URL
    private let queue = DispatchQueue(label: "com.yojam.logger")
    // P9: Hold open FileHandle to avoid open/close per log line
    private var openHandle: FileHandle?
    // §38: Static DateFormatter to avoid expensive allocation per log call
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private init() {
        logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Yojam")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "debugLogging") }

    /// Sanitize a URL for logging: strips query, fragment, and credentials
    /// to prevent OAuth/session tokens from ending up in log files.
    static func sanitize(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "[url]" }
        c.user = nil; c.password = nil; c.query = nil; c.fragment = nil
        return c.string ?? "[url]"
    }

    func log(_ message: String, file: String = #file, line: Int = #line) {
        // Cap message length to prevent log bloat from malicious URLs
        let capped = message.count > 2048 ? String(message.prefix(2048)) + "…[truncated]" : message
        osLog.info("\(capped)")
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        queue.async { [self] in
            let timestamp = dateFormatter.string(from: Date())
            let entry = "[\(timestamp)] [\(fileName):\(line)] \(capped)\n"
            let logFile = logDir.appendingPathComponent("yojam.log")

            // §45: Rotate log file if it exceeds 10MB
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
               let size = attrs[.size] as? UInt64, size > 10_000_000 {
                try? self.openHandle?.close()
                self.openHandle = nil
                let rotated = logDir.appendingPathComponent("yojam.log.1")
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: logFile, to: rotated)
            }

            // P9: Reuse open file handle
            if self.openHandle == nil {
                if !FileManager.default.fileExists(atPath: logFile.path) {
                    FileManager.default.createFile(atPath: logFile.path, contents: nil)
                }
                self.openHandle = try? FileHandle(forWritingTo: logFile)
            }
            if let handle = self.openHandle {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
            }
        }
    }
}
