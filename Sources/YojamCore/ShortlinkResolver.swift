import Foundation
import os

/// Opt-in async pre-stage that resolves shortlinks (bit.ly, t.co, etc.)
/// to their final destination before routing. NOT part of RoutingService.decide()
/// which remains pure and synchronous.
///
/// SSRF hardening: rejects private/loopback hosts, strips credentials,
/// uses HEAD-first with GET fallback, never auto-follows redirects.
public actor ShortlinkResolver {
    public static let shared = ShortlinkResolver()

    public static let defaultShortenerHosts: Set<String> = [
        "bit.ly", "t.co", "goo.gl", "tinyurl.com", "ow.ly", "buff.ly",
        "is.gd", "lnkd.in", "fb.me", "dlvr.it", "rebrand.ly", "cutt.ly",
        "tiny.cc", "shorturl.at", "t.ly", "rb.gy", "bl.ink"
    ]

    private var cache: [URL: (resolved: URL, expires: Date)] = [:]
    private let cacheMax = 256
    private let cacheTTL: TimeInterval = 3600

    private let logger = os.Logger(subsystem: "com.yojam.core", category: "shortlink")

    /// Resolves a shortlink to its final destination URL.
    /// Returns the original URL unchanged if the host is not in the allowlist
    /// or if resolution fails.
    public func resolve(
        _ url: URL,
        allowlist: Set<String> = defaultShortenerHosts,
        timeout: TimeInterval = 3.0,
        maxHops: Int = 5
    ) async -> URL {
        guard let host = url.host?.lowercased(), allowlist.contains(host) else { return url }
        if let cached = cache[url], cached.expires > Date() { return cached.resolved }

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = timeout
        config.httpAdditionalHeaders = ["User-Agent": "Yojam/1.0"]

        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        var current = url
        var visited: Set<URL> = []
        for _ in 0..<maxHops {
            if visited.contains(current) { break }
            visited.insert(current)

            // SSRF: reject private/loopback hosts
            guard let h = current.host, Self.isPublicHost(h) else { break }
            // Reject non-http(s)
            guard ["http", "https"].contains(current.scheme?.lowercased() ?? "") else { break }

            var req = URLRequest(url: current)
            req.httpMethod = "HEAD"
            req.setValue(nil, forHTTPHeaderField: "Cookie")

            do {
                let (_, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else { break }

                if http.statusCode == 405 || http.statusCode == 501 {
                    // Fallback to GET with tiny Range header
                    req.httpMethod = "GET"
                    req.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                    let (_, getResp) = try await session.data(for: req)
                    guard let httpGet = getResp as? HTTPURLResponse,
                          (301...308).contains(httpGet.statusCode),
                          let loc = httpGet.value(forHTTPHeaderField: "Location"),
                          let next = URL(string: loc, relativeTo: current)?.absoluteURL
                    else { break }
                    current = Self.stripCredentials(next)
                    continue
                }

                guard (301...308).contains(http.statusCode),
                      let loc = http.value(forHTTPHeaderField: "Location"),
                      let next = URL(string: loc, relativeTo: current)?.absoluteURL
                else { break }
                current = Self.stripCredentials(next)
            } catch {
                logger.warning("Shortlink resolution failed for \(current.absoluteString): \(error.localizedDescription)")
                break
            }
        }

        let resolved = current
        cache[url] = (resolved, Date().addingTimeInterval(cacheTTL))
        if cache.count > cacheMax {
            if let oldest = cache.min(by: { $0.value.expires < $1.value.expires })?.key {
                cache.removeValue(forKey: oldest)
            }
        }
        return resolved
    }

    /// SSRF hardening: reject private/loopback/link-local hosts.
    private static func isPublicHost(_ host: String) -> Bool {
        // Quick check for obvious private ranges in the hostname itself
        let lowered = host.lowercased()
        if lowered == "localhost" || lowered == "::1" { return false }

        // Parse as IPv4
        let parts = host.split(separator: ".")
        if parts.count == 4, let first = UInt8(parts[0]) {
            switch first {
            case 10: return false                    // 10/8
            case 127: return false                   // 127/8
            case 169:                                // 169.254/16
                if let second = UInt8(parts[1]), second == 254 { return false }
            case 172:                                // 172.16/12
                if let second = UInt8(parts[1]), (16...31).contains(second) { return false }
            case 192:                                // 192.168/16
                if let second = UInt8(parts[1]), second == 168 { return false }
            default: break
            }
        }

        // IPv6 simple checks
        if lowered.hasPrefix("fe80") || lowered.hasPrefix("fc") || lowered.hasPrefix("fd") {
            return false
        }

        return true
    }

    private static func stripCredentials(_ url: URL) -> URL {
        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        comps.user = nil; comps.password = nil
        return comps.url ?? url
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
