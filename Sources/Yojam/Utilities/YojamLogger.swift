import Foundation
import os

final class YojamLogger: @unchecked Sendable {
    static let shared = YojamLogger()
    private let osLog = os.Logger(subsystem: "com.yojam.app", category: "general")
    private let logDir: URL
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()
    private let queue = DispatchQueue(label: "com.yojam.logger")

    private init() {
        logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Yojam")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "debugLogging") }

    func log(_ message: String, file: String = #file, line: Int = #line) {
        osLog.info("\(message)")
        guard isEnabled else { return }
        let timestamp = dateFormatter.string(from: Date())
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let entry = "[\(timestamp)] [\(fileName):\(line)] \(message)\n"
        queue.async { [self] in
            let logFile = logDir.appendingPathComponent("yojam.log")
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                if let data = entry.data(using: .utf8) {
                    handle.write(data)
                }
                try? handle.close()
            } else {
                try? entry.data(using: .utf8)?.write(to: logFile)
            }
        }
    }
}
