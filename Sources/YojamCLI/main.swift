import Foundation
import YojamCore

// MARK: - CLI Entry Point

let args = CommandLine.arguments
let progName = URL(fileURLWithPath: args[0]).lastPathComponent

guard args.count >= 2 else {
    printUsage()
    exit(1)
}

let command = args[1].lowercased()

switch command {
case "open":
    handleOpen(Array(args.dropFirst(2)))
case "preview":
    handlePreview(Array(args.dropFirst(2)))
case "settings":
    handleSettings()
case "--version", "-v":
    print("yojam 1.0.0")
case "--help", "-h", "help":
    printUsage()
default:
    fputs("Unknown command: \(args[1])\n", stderr)
    printUsage()
    exit(1)
}

// MARK: - Commands

func handleOpen(_ args: [String]) {
    guard let urlArg = args.first else {
        fputs("Usage: \(progName) open <url> [--browser <id>] [--pick] [--private] [--source <sentinel>]\n", stderr)
        exit(1)
    }

    guard let url = validateURL(urlArg) else { exit(1) }

    var browser: String? = nil
    var pick = false
    var priv = false
    var source: String = SourceAppSentinel.cli

    var i = 1
    while i < args.count {
        switch args[i] {
        case "--browser":
            i += 1; guard i < args.count else { fputs("--browser requires a value\n", stderr); exit(1) }
            browser = args[i]
        case "--pick":
            pick = true
        case "--private":
            priv = true
        case "--source":
            i += 1; guard i < args.count else { fputs("--source requires a value\n", stderr); exit(1) }
            if SourceAppSentinel.all.contains(args[i]) {
                source = args[i]
            } else {
                fputs("Warning: untrusted source sentinel ignored, using cli\n", stderr)
            }
        default:
            fputs("Unknown flag: \(args[i])\n", stderr)
            exit(1)
        }
        i += 1
    }

    guard let yojamURL = YojamCommand.buildRoute(
        target: url, source: source, browser: browser,
        pick: pick, privateWindow: priv
    ) else {
        fputs("Failed to build route URL\n", stderr)
        exit(1)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [yojamURL.absoluteString]
    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            fputs("open failed with status \(process.terminationStatus)\n", stderr)
            exit(1)
        }
    } catch {
        fputs("Failed to launch: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

func handlePreview(_ args: [String]) {
    guard let urlArg = args.first else {
        fputs("Usage: \(progName) preview <url> [--json]\n", stderr)
        exit(1)
    }

    guard let url = validateURL(urlArg) else { exit(1) }

    let jsonOutput = args.contains("--json")

    let store = SharedRoutingStore(requireAppGroup: true)
    guard let config = RoutingSnapshotLoader.loadConfiguration(from: store) else {
        fputs("Cannot load routing configuration — check App Group entitlement\n", stderr)
        exit(1)
    }

    // Resolve shortlinks if enabled, to match real routing behavior
    var resolvedURL = url
    if config.shortlinkResolutionEnabled,
       let host = url.host?.lowercased(),
       ShortlinkResolver.defaultShortenerHosts.contains(host) {
        let sem = DispatchSemaphore(value: 0)
        Task {
            resolvedURL = await ShortlinkResolver.shared.resolve(url)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + .seconds(4))
    }

    let request = IncomingLinkRequest(
        url: resolvedURL,
        sourceAppBundleId: SourceAppSentinel.cli,
        origin: .urlScheme
    )
    let decision = RoutingService.decide(request: request, configuration: config)
    let preview = RouteDecisionPreview.from(decision)

    if jsonOutput {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(preview),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        } else {
            fputs("Failed to encode preview as JSON\n", stderr)
            exit(1)
        }
    } else {
        print(preview.summary)
        if let reason = preview.reason {
            print("  Reason: \(reason)")
        }
        print("  Final URL: \(preview.finalURL)")
        if let target = preview.targetDisplayName {
            print("  Target: \(target)")
        }
        if preview.privateWindow {
            print("  Private window: yes")
        }
        if let candidates = preview.pickerCandidates, !candidates.isEmpty {
            print("  Picker candidates:")
            for (i, c) in candidates.enumerated() {
                let marker = (c.displayName == preview.preselectedDisplayName) ? " *" : ""
                print("    \(i + 1). \(c.displayName) (\(c.bundleId))\(marker)")
            }
        }
    }
}

func handleSettings() {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["yojam://settings"]
    try? process.run()
    process.waitUntilExit()
}

// MARK: - Helpers

func validateURL(_ raw: String) -> URL? {
    guard raw.count <= 32_768 else {
        fputs("URL too long (max 32768 characters)\n", stderr)
        return nil
    }
    guard let url = URL(string: raw),
          let scheme = url.scheme?.lowercased(),
          ["http", "https", "mailto"].contains(scheme) else {
        fputs("Invalid URL: must be http, https, or mailto\n", stderr)
        return nil
    }
    // Reject recursive yojam:// URLs
    if url.scheme?.lowercased() == "yojam" {
        fputs("Cannot route yojam:// URLs\n", stderr)
        return nil
    }
    return url
}

func printUsage() {
    print("""
    Usage: \(progName) <command> [options]

    Commands:
      open <url>      Route a URL through Yojam
        --browser <id>  Force a specific browser bundle ID
        --pick          Show the browser picker
        --private       Open in a private window
        --source <id>   Set source sentinel

      preview <url>   Preview routing decision without opening
        --json          Output as JSON

      settings        Open Yojam preferences

      --version       Show version
    """)
}
