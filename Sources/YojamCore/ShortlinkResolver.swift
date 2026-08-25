import Darwin
import Foundation
import os

public enum ShortlinkResolutionMode: String, Codable, Sendable {
    /// Yojam 1.0 through 1.2.2 match HTTP and HTTPS by exact host.
    case exactHostHTTPAndHTTPS
    /// Yojam and Finicky 4 match HTTP and HTTPS hosts by domain suffix.
    case domainSuffixHTTPAndHTTPS
    /// Finicky 3 matches only an exact provider host over HTTPS.
    case exactHostHTTPS
}

/// Opt-in async pre-stage that resolves shortlinks (bit.ly, t.co, etc.)
/// to their final destination before routing. NOT part of RoutingService.decide()
/// which remains pure and synchronous.
///
/// SSRF hardening: rejects private/loopback hosts, strips credentials,
/// uses HEAD-first with GET fallback, never auto-follows redirects.
public actor ShortlinkResolver {
    public static let shared = ShortlinkResolver()

    typealias HostSafetyCheck = @Sendable (String) async -> Bool
    typealias HostAddressResolver = @Sendable (String) async -> [String]?
    typealias ResponseLoader = @Sendable (URLRequest, URLSession) async throws -> URLResponse

    /// The catalogue used by Yojam before imported Finicky policies were stored.
    /// Keep this fallback for users whose defaults have no host-policy key.
    public static let defaultShortenerHosts: Set<String> = [
        "bit.ly", "t.co", "goo.gl", "tinyurl.com", "ow.ly", "buff.ly",
        "is.gd", "lnkd.in", "fb.me", "dlvr.it", "rebrand.ly", "cutt.ly",
        "tiny.cc", "shorturl.at", "t.ly", "rb.gy", "bl.ink",
    ]

    /// Finicky 4's embedded catalogue. Keep this list in sync with
    /// `apps/finicky/src/shorturl/shortener_domains.json`.
    public static let finickyV4ShortenerHosts: Set<String> = [
        "aka.ms", "bit.ly", "buff.ly", "d.to", "dub.sh", "goo.gl",
        "is.gd", "linkprotect.cudasvc.com", "msteams.link", "ow.ly",
        "safelinks.protection.outlook.com", "shorturl.at", "spoti.fi",
        "t.co", "tiny.cc", "tinyurl.com",
        "urlshortener.teams.microsoft.com", "wu8.in",
    ]

    /// Finicky 3's default `defaultUrlShorteners` value.
    public static let finickyV3ShortenerHosts: Set<String> = [
        "adf.ly", "bit.do", "bit.ly", "buff.ly", "deck.ly", "fur.ly",
        "goo.gl", "is.gd", "mcaf.ee", "ow.ly", "spoti.fi", "su.pr",
        "t.co", "tiny.cc", "tinyurl.com",
    ]

    private struct CacheKey: Hashable {
        let url: URL
        let allowlist: [String]
        let mode: ShortlinkResolutionMode
    }

    private var cache: [CacheKey: (resolved: URL, expires: Date)] = [:]
    private let cacheMax = 256
    private let cacheTTL: TimeInterval = 3600
    private let resolvePublicAddresses: HostAddressResolver
    private let responseLoader: ResponseLoader

    private let logger = os.Logger(subsystem: "com.yojam.core", category: "shortlink")

    init() {
        resolvePublicAddresses = { host in
            await NetworkHostSafety.publicAddresses(for: host)
        }
        responseLoader = { request, _ in
            guard let addresses = ShortlinkRequestContext.pinnedAddresses,
                  !addresses.isEmpty else {
                throw URLError(.cannotFindHost)
            }
            return try await PinnedCurlTransport.load(
                request,
                pinnedAddresses: addresses)
        }
    }

    init(
        hostIsPublic: @escaping HostSafetyCheck,
        responseLoader: @escaping ResponseLoader = { request, session in
            let (_, response) = try await session.bytes(for: request)
            return response
        }
    ) {
        resolvePublicAddresses = { host in
            await hostIsPublic(host) ? ["test-public-address"] : nil
        }
        self.responseLoader = responseLoader
    }

    init(
        resolvePublicAddresses: @escaping HostAddressResolver,
        responseLoader: @escaping ResponseLoader
    ) {
        self.resolvePublicAddresses = resolvePublicAddresses
        self.responseLoader = responseLoader
    }

    /// Resolves a shortlink to its final destination URL.
    /// Returns the original URL unchanged if the host is not in the allowlist
    /// or if resolution fails.
    public func resolve(
        _ url: URL,
        allowlist: Set<String> = defaultShortenerHosts,
        mode: ShortlinkResolutionMode = .exactHostHTTPAndHTTPS,
        timeout: TimeInterval = 3.0,
        maxHops: Int = 5
    ) async -> URL {
        let original = Self.stripCredentials(url)
        let canonicalAllowlist = Self.canonicalHostAllowlist(allowlist)
        guard timeout > 0,
              Self.isConfiguredShortlinkURL(
                original,
                allowlist: canonicalAllowlist,
                mode: mode)
        else { return original }
        let cacheKey = CacheKey(
            url: original,
            allowlist: canonicalAllowlist.sorted(),
            mode: mode)
        if let cached = cache[cacheKey], cached.expires > Date() { return cached.resolved }

        let deadline = Date().addingTimeInterval(timeout)

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout
        config.httpAdditionalHeaders = ["User-Agent": "Yojam/1.0"]

        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var current = original
        var visited: Set<URL> = []
        var validatedAddresses: [URL: [String]] = [:]
        for _ in 0..<maxHops {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return original }
            if visited.contains(current) { break }
            visited.insert(current)

            // Reject non-http(s)
            let addresses: [String]
            if let validated = validatedAddresses[current] {
                addresses = validated
            } else if let validated = await safeNetworkAddresses(
                for: current,
                deadline: deadline) {
                addresses = validated
                validatedAddresses[current] = validated
            } else {
                return original
            }
            guard !addresses.isEmpty else { return original }

            let requestRemaining = deadline.timeIntervalSinceNow
            guard requestRemaining > 0 else { return original }

            var req = URLRequest(url: current)
            req.timeoutInterval = requestRemaining
            req.httpMethod = "HEAD"
            req.setValue(nil, forHTTPHeaderField: "Cookie")

            do {
                let response = try await loadResponse(
                    for: req,
                    session: session,
                    deadline: deadline,
                    pinnedAddresses: addresses)
                guard let http = response as? HTTPURLResponse else { break }

                if http.statusCode == 405 || http.statusCode == 501 {
                    // Ask only for headers and one byte. `bytes(for:)` returns
                    // after the response starts and does not buffer its body.
                    let getRemaining = deadline.timeIntervalSinceNow
                    guard getRemaining > 0 else { return original }
                    req.httpMethod = "GET"
                    req.timeoutInterval = getRemaining
                    req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                    let getResp = try await loadResponse(
                        for: req,
                        session: session,
                        deadline: deadline,
                        pinnedAddresses: addresses)
                    guard let httpGet = getResp as? HTTPURLResponse,
                          Self.isRedirectStatus(httpGet.statusCode),
                          let loc = httpGet.value(forHTTPHeaderField: "Location"),
                          let next = URL(string: loc, relativeTo: current)?.absoluteURL
                    else { break }
                    let candidate = Self.stripCredentials(next)
                    guard Self.isSafeRedirectTarget(candidate) else { return original }
                    guard Self.isConfiguredShortlinkURL(
                        candidate,
                        allowlist: canonicalAllowlist,
                        mode: mode)
                    else { return candidate }
                    guard let candidateAddresses = await safeNetworkAddresses(
                        for: candidate,
                        deadline: deadline) else {
                        return original
                    }
                    validatedAddresses[candidate] = candidateAddresses
                    current = candidate
                    continue
                }

                guard Self.isRedirectStatus(http.statusCode),
                      let loc = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL
                else { break }
                let candidate = Self.stripCredentials(next)
                guard Self.isSafeRedirectTarget(candidate) else { return original }
                guard Self.isConfiguredShortlinkURL(
                    candidate,
                    allowlist: canonicalAllowlist,
                    mode: mode)
                else { return candidate }
                guard let candidateAddresses = await safeNetworkAddresses(
                    for: candidate,
                    deadline: deadline) else {
                    return original
                }
                validatedAddresses[candidate] = candidateAddresses
                current = candidate
            } catch {
                let logURL = Self.redactedLogURL(current)
                logger.warning(
                    "Shortlink resolution failed for \(logURL): \(error.localizedDescription)")
                return original
            }
        }

        let resolved = current
        cache[cacheKey] = (resolved, Date().addingTimeInterval(cacheTTL))
        if cache.count > cacheMax {
            if let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
                cache.removeValue(forKey: oldest)
            }
        }
        return resolved
    }

    private func safeNetworkAddresses(
        for url: URL,
        deadline: Date
    ) async -> [String]? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host
        else { return nil }
        let resolver = resolvePublicAddresses
        return (try? await beforeDeadline(deadline) {
            await resolver(host)
        }) ?? nil
    }

    private func loadResponse(
        for request: URLRequest,
        session: URLSession,
        deadline: Date,
        pinnedAddresses: [String]
    ) async throws -> URLResponse {
        let loader = responseLoader
        return try await beforeDeadline(deadline) {
            try await ShortlinkRequestContext.$pinnedAddresses.withValue(
                pinnedAddresses) {
                try await loader(request, session)
            }
        }
    }

    private func beforeDeadline<Value: Sendable>(
        _ deadline: Date,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else { throw URLError(.timedOut) }
        let cancellation = DeadlineCancellationBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = DeadlineRaceState(continuation: continuation)
                cancellation.install {
                    state.finish(.failure(CancellationError()))
                }
                let operationTask = Task {
                    do {
                        state.finish(.success(try await operation()))
                    } catch {
                        state.finish(.failure(error))
                    }
                }
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(
                            nanoseconds: UInt64(remaining * 1_000_000_000))
                        state.finish(.failure(URLError(.timedOut)))
                    } catch {
                        // The operation completed and cancelled this timer.
                    }
                }
                state.install(operationTask: operationTask, timeoutTask: timeoutTask)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private static func isSafeRedirectTarget(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host
        else { return false }
        return NetworkHostSafety.isSafeLiteralHost(host)
    }

    public static func isConfiguredShortlinkHost(
        _ host: String,
        allowlist: Set<String> = defaultShortenerHosts,
        mode: ShortlinkResolutionMode = .exactHostHTTPAndHTTPS
    ) -> Bool {
        let normalisedHost = host.lowercased()
        return allowlist.contains { domain in
            let normalisedDomain = domain.lowercased()
            switch mode {
            case .domainSuffixHTTPAndHTTPS:
                return normalisedHost == normalisedDomain
                    || normalisedHost.hasSuffix(".\(normalisedDomain)")
            case .exactHostHTTPAndHTTPS, .exactHostHTTPS:
                return normalisedHost == normalisedDomain
            }
        }
    }

    public static func isConfiguredShortlinkURL(
        _ url: URL,
        allowlist: Set<String> = defaultShortenerHosts,
        mode: ShortlinkResolutionMode = .exactHostHTTPAndHTTPS
    ) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              let host = url.host,
              ["http", "https"].contains(scheme)
        else { return false }
        if mode == .exactHostHTTPS, scheme != "https" { return false }
        return isConfiguredShortlinkHost(host, allowlist: allowlist, mode: mode)
    }

    /// Produces the stable representation stored in shared defaults.
    public static func canonicalHostAllowlist<S: Sequence>(_ hosts: S) -> Set<String>
    where S.Element == String {
        Set(hosts.compactMap(canonicalHost))
    }

    public static func canonicalHost(_ value: String) -> String? {
        var host = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty,
              host.count <= 253,
              !host.contains("/"),
              !host.contains(":"),
              !host.contains("@"),
              !host.contains("*"),
              host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ label in
                !label.isEmpty && label.count <= 63
                    && label.first != "-" && label.last != "-"
                    && label.allSatisfy { character in
                        character.isASCII
                            && (character.isLetter || character.isNumber || character == "-")
                    }
              })
        else { return nil }
        return host
    }

    private static func isRedirectStatus(_ statusCode: Int) -> Bool {
        [301, 302, 303, 307, 308].contains(statusCode)
    }

    static func redactedLogURL(_ url: URL) -> String {
        guard let scheme = url.scheme?.lowercased(), let host = url.host else {
            return "<invalid URL>"
        }
        return "\(scheme)://\(host)"
    }

    private static func stripCredentials(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        comps.user = nil; comps.password = nil
        return comps.url ?? url
    }
}

private final class DeadlineRaceState<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var isFinished = false

    init(continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func install(
        operationTask: Task<Void, Never>,
        timeoutTask: Task<Void, Never>
    ) {
        lock.lock()
        if isFinished {
            lock.unlock()
            operationTask.cancel()
            timeoutTask.cancel()
            return
        }
        self.operationTask = operationTask
        self.timeoutTask = timeoutTask
        lock.unlock()
    }

    func finish(_ result: sending Result<Value, Error>) {
        lock.lock()
        guard !isFinished, let continuation else {
            lock.unlock()
            return
        }
        isFinished = true
        self.continuation = nil
        let operationTask = self.operationTask
        let timeoutTask = self.timeoutTask
        lock.unlock()

        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(with: result)
    }
}

private final class DeadlineCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var action: (@Sendable () -> Void)?
    private var isCancelled = false

    func install(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            action()
            return
        }
        self.action = action
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let action = action
        lock.unlock()
        action?()
    }
}

private enum ShortlinkRequestContext {
    @TaskLocal static var pinnedAddresses: [String]?
}

enum PinnedCurlTransport {
    fileprivate struct Output: Sendable {
        var status: Int32
        var headers: Data
    }

    static func load(
        _ request: URLRequest,
        pinnedAddresses: [String]
    ) async throws -> URLResponse {
        let arguments = try arguments(
            for: request,
            pinnedAddresses: pinnedAddresses)
        let configuration = try standardInputConfiguration(for: request)
        let cancellation = CurlProcessCancellationBox()
        let worker = Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            let input = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = input

            guard try cancellation.run(process: process) else {
                throw CancellationError()
            }
            do {
                try input.fileHandleForWriting.write(contentsOf: configuration)
                try input.fileHandleForWriting.close()
            } catch {
                if process.isRunning { process.terminate() }
                cancellation.clear(process: process)
                throw error
            }
            process.waitUntilExit()
            cancellation.clear(process: process)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            try Task.checkCancellation()
            return Output(status: process.terminationStatus, headers: data)
        }
        cancellation.install(task: worker)

        let output = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            cancellation.cancel()
        }
        if let response = response(from: output.headers, requestURL: request.url) {
            return response
        }
        guard output.status == 0 else { throw URLError(.cannotConnectToHost) }
        throw URLError(.badServerResponse)
    }

    static func arguments(
        for request: URLRequest,
        pinnedAddresses: [String]
    ) throws -> [String] {
        guard let url = request.url,
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.user == nil,
              url.password == nil,
              let host = url.host,
              !pinnedAddresses.isEmpty,
              pinnedAddresses.allSatisfy(isIPAddress)
        else { throw URLError(.unsupportedURL) }
        let port = url.port ?? (scheme == "https" ? 443 : 80)
        guard (1...65_535).contains(port) else { throw URLError(.badURL) }
        let timeout = max(0.001, request.timeoutInterval)
        let timeoutText = String(
            format: "%.3f",
            locale: Locale(identifier: "en_US_POSIX"),
            timeout)
        let addresses = pinnedAddresses.map { address in
            address.contains(":") ? "[\(address)]" : address
        }.joined(separator: ",")

        var result = [
            "-q",
            "--silent", "--show-error",
            "--noproxy", "*",
            "--max-redirs", "0",
            "--connect-timeout", timeoutText,
            "--max-time", timeoutText,
            "--proto", "=http,https",
            "--proto-redir", "=http,https",
            "--resolve", "\(host):\(port):\(addresses)",
            "--dump-header", "-",
            "--output", "/dev/null",
        ]
        switch request.httpMethod?.uppercased() {
        case "HEAD":
            result.append("--head")
        case "GET":
            result.append(contentsOf: ["--request", "GET", "--range", "0-0"])
        default:
            throw URLError(.unsupportedURL)
        }
        if let userAgent = request.value(forHTTPHeaderField: "User-Agent") {
            result.append(contentsOf: ["--user-agent", userAgent])
        }
        // The URL can contain private tokens. Feed it over stdin so another
        // process owned by the same user cannot read it from curl's argv.
        result.append(contentsOf: ["--config", "-"])
        return result
    }

    private static func standardInputConfiguration(
        for request: URLRequest
    ) throws -> Data {
        guard let value = request.url?.absoluteString,
              !value.contains("\r"),
              !value.contains("\n"),
              !value.contains("\\"),
              !value.contains("\"") else {
            throw URLError(.badURL)
        }
        return Data("url = \"\(value)\"\n".utf8)
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        if inet_pton(AF_INET, value, &ipv4) == 1 { return true }
        var ipv6 = in6_addr()
        return inet_pton(AF_INET6, value, &ipv6) == 1
    }

    private static func response(
        from data: Data,
        requestURL: URL?
    ) -> HTTPURLResponse? {
        guard let requestURL,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalised.components(separatedBy: "\n\n").reversed()
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: true)
            guard let statusLine = lines.first,
                  statusLine.hasPrefix("HTTP/"),
                  let status = statusLine.split(separator: " ").dropFirst().first,
                  let statusCode = Int(status) else { continue }
            var fields: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let name = String(line[..<colon])
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                fields[name] = value
            }
            return HTTPURLResponse(
                url: requestURL,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: fields)
        }
        return nil
    }
}

private final class CurlProcessCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var process: Process?
    private var task: Task<PinnedCurlTransport.Output, Error>?

    func run(process: Process) throws -> Bool {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return false
        }
        self.process = process
        do {
            try process.run()
        } catch {
            self.process = nil
            lock.unlock()
            throw error
        }
        lock.unlock()
        return true
    }

    func clear(process: Process) {
        lock.lock()
        if self.process === process { self.process = nil }
        lock.unlock()
    }

    func install(task: Task<PinnedCurlTransport.Output, Error>) {
        lock.lock()
        self.task = task
        let shouldCancel = isCancelled
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let process = process
        let task = task
        lock.unlock()
        task?.cancel()
        if process?.isRunning == true { process?.terminate() }
    }
}

enum NetworkHostSafety {
    static func isSafeLiteralHost(_ host: String) -> Bool {
        let lowered = host.lowercased()
        guard lowered != "localhost", !lowered.hasSuffix(".localhost") else {
            return false
        }

        var ipv4 = in_addr()
        if inet_pton(AF_INET, host, &ipv4) == 1 {
            var copy = ipv4
            return isPublicAddress(withUnsafeBytes(of: &copy) { Array($0) })
        }
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, host, &ipv6) == 1 {
            var copy = ipv6
            return isPublicAddress(withUnsafeBytes(of: &copy) { Array($0) })
        }
        // A colon which is not a valid IPv6 literal is not a DNS hostname.
        return !host.contains(":")
    }

    static func isPublic(_ host: String) async -> Bool {
        await publicAddresses(for: host) != nil
    }

    static func publicAddresses(for host: String) async -> [String]? {
        guard isSafeLiteralHost(host) else { return nil }

        return await Task.detached(priority: .utility) {
            guard let addresses = resolvedAddresses(for: host), !addresses.isEmpty else {
                return nil
            }
            guard addresses.allSatisfy(isPublicAddress) else { return nil }
            var seen = Set<String>()
            let strings = addresses.compactMap(stringAddress).filter {
                seen.insert($0).inserted
            }
            return strings.count == Set(addresses).count && !strings.isEmpty
                ? strings
                : nil
        }.value
    }

    static func isPublicAddress(_ bytes: [UInt8]) -> Bool {
        switch bytes.count {
        case 4:
            return isPublicIPv4(bytes)
        case 16:
            return isPublicIPv6(bytes)
        default:
            return false
        }
    }

    private static func isPublicIPv4(_ address: [UInt8]) -> Bool {
        let first = address[0]
        let second = address[1]

        if first == 0 || first == 10 || first == 127 { return false }
        if first == 100, (64...127).contains(second) { return false }
        if first == 169, second == 254 { return false }
        if first == 172, (16...31).contains(second) { return false }
        if first == 192, second == 0, address[2] == 0 { return false }
        if first == 192, second == 0, address[2] == 2 { return false }
        if first == 192, second == 88, address[2] == 99 { return false }
        if first == 192, second == 168 { return false }
        if first == 198, second == 18 || second == 19 { return false }
        if first == 198, second == 51, address[2] == 100 { return false }
        if first == 203, second == 0, address[2] == 113 { return false }
        if first >= 224 { return false }
        return true
    }

    private static func isPublicIPv6(_ address: [UInt8]) -> Bool {
        // IPv4-mapped IPv6 and 6to4 addresses keep the embedded IPv4 risk.
        if address[0..<10].allSatisfy({ $0 == 0 }),
           address[10] == 0xff,
           address[11] == 0xff {
            return isPublicIPv4(Array(address[12..<16]))
        }
        // Only globally routable unicast space is valid for this network request.
        guard address[0] & 0xe0 == 0x20 else { return false }
        // 2001:0000::/23 contains protocol assignments such as Teredo,
        // benchmarking ranges, ORCHID, and other special-purpose addresses.
        if address[0] == 0x20, address[1] == 0x01,
           address[2] <= 0x01 {
            return false
        }
        // 6to4 is deprecated and does not provide a stable globally routed
        // endpoint suitable for a pinned security decision.
        if address[0] == 0x20, address[1] == 0x02 { return false }
        if address[0] == 0x20, address[1] == 0x01,
           address[2] == 0x0d, address[3] == 0xb8 {
            return false
        }
        // 3fff::/20 is reserved for documentation.
        if address[0] == 0x3f, address[1] == 0xff,
           (address[2] & 0xf0) == 0 {
            return false
        }
        return true
    }

    private static func resolvedAddresses(for host: String) -> [[UInt8]]? {
        var hints = addrinfo()
        hints.ai_flags = AI_ADDRCONFIG
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else {
            return nil
        }
        defer { freeaddrinfo(first) }

        var addresses: [[UInt8]] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            switch info.pointee.ai_family {
            case AF_INET:
                let socketAddress = UnsafeRawPointer(info.pointee.ai_addr)
                    .assumingMemoryBound(to: sockaddr_in.self)
                    .pointee
                var address = socketAddress.sin_addr
                addresses.append(withUnsafeBytes(of: &address) { Array($0) })
            case AF_INET6:
                let socketAddress = UnsafeRawPointer(info.pointee.ai_addr)
                    .assumingMemoryBound(to: sockaddr_in6.self)
                    .pointee
                var address = socketAddress.sin6_addr
                addresses.append(withUnsafeBytes(of: &address) { Array($0) })
            default:
                break
            }
            cursor = info.pointee.ai_next
        }
        return addresses
    }

    private static func stringAddress(_ bytes: [UInt8]) -> String? {
        let family: Int32
        switch bytes.count {
        case 4: family = AF_INET
        case 16: family = AF_INET6
        default: return nil
        }
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        let result = bytes.withUnsafeBytes { rawBuffer in
            inet_ntop(
                family,
                rawBuffer.baseAddress,
                &buffer,
                socklen_t(buffer.count))
        }
        guard result != nil else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil) // Never auto-follow; we drive it manually
    }
}
