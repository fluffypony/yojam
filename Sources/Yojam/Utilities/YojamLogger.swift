import Foundation
import os

final class YojamLogger: @unchecked Sendable {
    static let shared = YojamLogger()
    private let osLog = os.Logger(subsystem: "com.yojam.app", category: "general")
    private let logDir: URL
    private let queue = DispatchQueue(label: "com.yojam.logger")
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

    func log(_ message: String, file: String = #file, line: Int = #line) {
        osLog.info("\(message)")
        guard isEnabled else { return }
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        queue.async { [self] in
            let timestamp = dateFormatter.string(from: Date())
            let entry = "[\(timestamp)] [\(fileName):\(line)] \(message)\n"
            let logFile = logDir.appendingPathComponent("yojam.log")

            // §45: Rotate log file if it exceeds 10MB
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
               let size = attrs[.size] as? UInt64, size > 10_000_000 {
                let rotated = logDir.appendingPathComponent("yojam.log.1")
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: logFile, to: rotated)
            }

            // §46: Always use FileHandle append; never fall back to overwrite
            if let handle = try? FileHandle(forWritingTo: logFile) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
            } else {
                // File doesn't exist yet — create it
                try? entry.data(using: .utf8)?.write(to: logFile)
            }
        }
    }
}
