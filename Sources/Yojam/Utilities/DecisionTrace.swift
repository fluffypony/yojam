import Foundation
import YojamCore

/// Opt-in structured JSONL log of routing decisions.
/// Each call to `log()` writes one line to ~/Library/Logs/Yojam/decisions.jsonl.
/// Enabled via the Debug Logging toggle in Advanced preferences.
final class DecisionTrace: @unchecked Sendable {
    static let shared = DecisionTrace()

    private let logDir: URL
    private let queue = DispatchQueue(label: "com.yojam.decisiontrace")

    private init() {
        logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Yojam")
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: "debugLogging") }

    func log(
        inputURL: URL,
        decision: RouteDecision,
        request: IncomingLinkRequest
    ) {
        guard isEnabled else { return }
        let entry = TraceEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            inputURL: sanitize(request.url),
            finalURL: sanitize(decisionURL(decision)),
            decision: decisionKind(decision),
            target: decisionTarget(decision),
            reason: decisionReason(decision),
            source: request.sourceAppBundleId ?? "unknown",
            origin: String(describing: request.origin)
        )
        queue.async { [self] in
            guard let data = try? JSONEncoder().encode(entry),
                  var line = String(data: data, encoding: .utf8) else { return }
            line += "\n"
            let logFile = logDir.appendingPathComponent("decisions.jsonl")

            // Rotate at 10MB
            if let attrs = try? FileManager.default.attributesOfItem(atPath: logFile.path),
               let size = attrs[.size] as? UInt64, size > 10_000_000 {
                let rotated = logDir.appendingPathComponent("decisions.jsonl.1")
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: logFile, to: rotated)
            }

            if let handle = try? FileHandle(forWritingTo: logFile) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) { handle.write(data) }
            } else {
                try? line.data(using: .utf8)?.write(to: logFile)
            }
        }
    }

    private func sanitize(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "[url]" }
        c.user = nil; c.password = nil; c.query = nil; c.fragment = nil
        return c.string ?? "[url]"
    }

    private func decisionURL(_ d: RouteDecision) -> URL {
        switch d {
        case .openDirect(_, let url, _, _): url
        case .showPicker(_, _, let url, _, _): url
        case .openSystemDefault(let url): url
        case .openSystemMailHandler(let url): url
        }
    }

    private func decisionKind(_ d: RouteDecision) -> String {
        switch d {
        case .openDirect: "openDirect"
        case .showPicker: "showPicker"
        case .openSystemDefault: "openSystemDefault"
        case .openSystemMailHandler: "openSystemMailHandler"
        }
    }

    private func decisionTarget(_ d: RouteDecision) -> String? {
        switch d {
        case .openDirect(let b, _, _, _): b.fullDisplayName
        default: nil
        }
    }

    private func decisionReason(_ d: RouteDecision) -> String? {
        switch d {
        case .openDirect(_, _, _, let r): r
        case .showPicker(_, _, _, _, let r): r
        default: nil
        }
    }
}

private struct TraceEntry: Encodable {
    let timestamp: String
    let inputURL: String
    let finalURL: String
    let decision: String
    let target: String?
    let reason: String?
    let source: String
    let origin: String
}
