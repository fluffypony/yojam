import Foundation
import YojamCore

signal(SIGPIPE, SIG_IGN)

// MARK: - Native Messaging Protocol (length-prefixed JSON over stdio)

/// Reads a single length-prefixed JSON message from stdin.
func readMessage() -> HostRequest? {
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    var totalRead = 0
    while totalRead < 4 {
        let n = lengthBytes.withUnsafeMutableBufferPointer { buf -> Int in
            fread(buf.baseAddress! + totalRead, 1, 4 - totalRead, stdin)
        }
        if n == 0 { return nil } // clean EOF or error
        totalRead += n
    }
    let length = UInt32(lengthBytes[0])
        | (UInt32(lengthBytes[1]) << 8)
        | (UInt32(lengthBytes[2]) << 16)
        | (UInt32(lengthBytes[3]) << 24)
    guard length > 0, length < 1_048_576 else { return nil }

    var buffer = [UInt8](repeating: 0, count: Int(length))
    var bodyRead = 0
    while bodyRead < Int(length) {
        let n = buffer.withUnsafeMutableBufferPointer { buf -> Int in
            fread(buf.baseAddress! + bodyRead, 1, Int(length) - bodyRead, stdin)
        }
        if n == 0 { return nil }
        bodyRead += n
    }
    let data = Data(buffer)
    return try? JSONDecoder().decode(HostRequest.self, from: data)
}

/// Writes a length-prefixed JSON message to stdout.
/// Has a hardcoded fallback when encoding fails so the extension never hangs.
func writeMessage(_ response: HostResponse) {
    let data: Data
    if let encoded = try? JSONEncoder().encode(response) {
        data = encoded
    } else {
        // Hardcoded fallback when encoding fails
        data = Data(#"{"ok":false,"error":"encode_failed"}"#.utf8)
    }
    var length = UInt32(data.count)
    let lengthBytes = withUnsafeBytes(of: &length) { Array($0) }
    fwrite(lengthBytes, 1, 4, stdout)
    data.withUnsafeBytes { ptr in
        fwrite(ptr.baseAddress, 1, data.count, stdout)
    }
    fflush(stdout)
}

/// Validate that source is a trusted sentinel, else fall back to chromeExtension.
func validatedSource(_ raw: String?) -> String {
    guard let raw, SourceAppSentinel.all.contains(raw) else {
        return SourceAppSentinel.chromeExtension
    }
    return raw
}

// MARK: - Request / Response Types

struct HostRequest: Decodable {
    let action: String    // "route" | "preview"
    let url: String
    let source: String?
    let modifiers: [String]?
    let forceBrowser: String?
    let forcePicker: Bool?
    let forcePrivate: Bool?
}

struct HostResponse: Encodable {
    let ok: Bool
    let preview: RouteDecisionPreview?
    let error: String?
}

// MARK: - Main Loop

while let req = readMessage() {
    switch req.action {
    case "route":
        guard let targetURL = URL(string: req.url),
              let scheme = targetURL.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme),
              req.url.count <= 32_768
        else {
            writeMessage(HostResponse(ok: false, preview: nil, error: "Invalid URL"))
            break
        }

        let source = validatedSource(req.source)
        if let yojamURL = YojamCommand.buildRoute(
            target: targetURL, source: source,
            browser: req.forceBrowser,
            pick: req.forcePicker ?? false,
            privateWindow: req.forcePrivate ?? false
        ) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [yojamURL.absoluteString]

            do {
                try process.run()
                let sem = DispatchSemaphore(value: 0)
                DispatchQueue.global().async { process.waitUntilExit(); sem.signal() }
                if sem.wait(timeout: .now() + .seconds(10)) == .timedOut {
                    process.terminate()
                    writeMessage(HostResponse(ok: false, preview: nil, error: "open timed out"))
                } else if process.terminationStatus != 0 {
                    writeMessage(HostResponse(ok: false, preview: nil,
                                              error: "open failed (\(process.terminationStatus))"))
                } else {
                    writeMessage(HostResponse(ok: true, preview: nil, error: nil))
                }
            } catch {
                writeMessage(HostResponse(ok: false, preview: nil,
                                          error: "Launch failed: \(error.localizedDescription)"))
            }
        } else {
            writeMessage(HostResponse(ok: false, preview: nil, error: "Failed to build route URL"))
        }

    case "preview":
        guard let targetURL = URL(string: req.url),
              let scheme = targetURL.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme),
              req.url.count <= 32_768
        else {
            writeMessage(HostResponse(ok: false, preview: nil, error: "Invalid URL"))
            continue  // preview is NOT one-shot; keep loop running
        }

        let store = SharedRoutingStore(requireAppGroup: true)
        guard let config = RoutingSnapshotLoader.loadConfiguration(from: store) else {
            writeMessage(HostResponse(ok: false, preview: nil, error: "Cannot load config"))
            continue
        }

        // Resolve shortlinks if enabled, to match real routing behavior
        var resolvedURL = targetURL
        if config.shortlinkResolutionEnabled,
           let host = targetURL.host?.lowercased(),
           ShortlinkResolver.defaultShortenerHosts.contains(host) {
            let sem = DispatchSemaphore(value: 0)
            Task {
                resolvedURL = await ShortlinkResolver.shared.resolve(targetURL)
                sem.signal()
            }
            _ = sem.wait(timeout: .now() + .seconds(4))
        }

        let source = validatedSource(req.source)
        let shiftHeld = req.modifiers?.contains("shift") ?? false
        let request = IncomingLinkRequest(
            url: resolvedURL,
            sourceAppBundleId: source,
            origin: .urlScheme,
            modifierFlags: shiftHeld ? (1 << 17) : 0,
            forcedBrowserBundleId: req.forceBrowser,
            forcePicker: req.forcePicker ?? false,
            forcePrivateWindow: req.forcePrivate ?? false
        )
        let decision = RoutingService.decide(request: request, configuration: config)
        writeMessage(HostResponse(ok: true, preview: .from(decision), error: nil))
        // IMPORTANT: do NOT break — keep processing further preview messages

    default:
        writeMessage(HostResponse(ok: false, preview: nil, error: "Unknown action: \(req.action)"))
    }

    // One-shot for route actions only: the extension opens a new host per message.
    if req.action == "route" { break }
}
