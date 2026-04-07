import Foundation
import YojamCore

// MARK: - Native Messaging Protocol (length-prefixed JSON over stdio)

/// Reads a single length-prefixed JSON message from stdin.
func readMessage() -> HostRequest? {
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    guard fread(&lengthBytes, 1, 4, stdin) == 4 else { return nil }
    let length = UInt32(lengthBytes[0])
        | (UInt32(lengthBytes[1]) << 8)
        | (UInt32(lengthBytes[2]) << 16)
        | (UInt32(lengthBytes[3]) << 24)
    guard length > 0, length < 1_048_576 else { return nil }

    var buffer = [UInt8](repeating: 0, count: Int(length))
    guard fread(&buffer, 1, Int(length), stdin) == Int(length) else { return nil }
    let data = Data(buffer)
    return try? JSONDecoder().decode(HostRequest.self, from: data)
}

/// Writes a length-prefixed JSON message to stdout.
func writeMessage(_ response: HostResponse) {
    guard let data = try? JSONEncoder().encode(response) else { return }
    var length = UInt32(data.count)
    let lengthBytes = withUnsafeBytes(of: &length) { Array($0) }
    fwrite(lengthBytes, 1, 4, stdout)
    data.withUnsafeBytes { ptr in
        fwrite(ptr.baseAddress, 1, data.count, stdout)
    }
    fflush(stdout)
}

// MARK: - Request / Response Types

struct HostRequest: Decodable {
    let action: String    // "route" | "preview"
    let url: String
    let source: String?
}

struct HostResponse: Encodable {
    let ok: Bool
    let target: String?
    let error: String?
}

// MARK: - Main Loop

while let req = readMessage() {
    switch req.action {
    case "route":
        guard let targetURL = URL(string: req.url),
              let scheme = targetURL.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme)
        else {
            writeMessage(HostResponse(ok: false, target: nil, error: "Invalid URL"))
            break
        }

        // Build a yojam:// URL and open it to forward to the main app.
        let source = req.source ?? SourceAppSentinel.chromeExtension
        if let yojamURL = YojamCommand.buildRoute(target: targetURL, source: source) {
            // Use /usr/bin/open to launch the yojam:// URL. The native host
            // runs as a bare tool with no AppKit, so NSWorkspace is unavailable.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [yojamURL.absoluteString]
            try? process.run()
            process.waitUntilExit()
            writeMessage(HostResponse(ok: true, target: nil, error: nil))
        } else {
            writeMessage(HostResponse(ok: false, target: nil, error: "Failed to build route URL"))
        }

    case "preview":
        // Future: return the RouteDecision without opening anything.
        // For now, return a simple acknowledgment.
        writeMessage(HostResponse(ok: true, target: nil, error: nil))

    default:
        writeMessage(HostResponse(ok: false, target: nil, error: "Unknown action: \(req.action)"))
    }

    // One-shot for route actions: the extension opens a new host per message.
    if req.action == "route" { break }
}
