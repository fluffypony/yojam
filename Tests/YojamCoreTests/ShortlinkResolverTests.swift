import XCTest

@testable import YojamCore

final class ShortlinkResolverTests: XCTestCase {
    func testCataloguesMatchEachSourcePolicyExactly() {
        XCTAssertEqual(ShortlinkResolver.defaultShortenerHosts, [
            "bit.ly", "t.co", "goo.gl", "tinyurl.com", "ow.ly", "buff.ly",
            "is.gd", "lnkd.in", "fb.me", "dlvr.it", "rebrand.ly", "cutt.ly",
            "tiny.cc", "shorturl.at", "t.ly", "rb.gy", "bl.ink",
        ])
        XCTAssertEqual(ShortlinkResolver.finickyV3ShortenerHosts, [
            "adf.ly", "bit.do", "bit.ly", "buff.ly", "deck.ly", "fur.ly",
            "goo.gl", "is.gd", "mcaf.ee", "ow.ly", "spoti.fi", "su.pr",
            "t.co", "tiny.cc", "tinyurl.com",
        ])
        XCTAssertEqual(ShortlinkResolver.finickyV4ShortenerHosts, [
            "aka.ms", "bit.ly", "buff.ly", "d.to", "dub.sh", "goo.gl",
            "is.gd", "linkprotect.cudasvc.com", "msteams.link", "ow.ly",
            "safelinks.protection.outlook.com", "shorturl.at", "spoti.fi",
            "t.co", "tiny.cc", "tinyurl.com",
            "urlshortener.teams.microsoft.com", "wu8.in",
        ])
    }

    func testShortenerMatchModesPreserveLegacyAndFinickySemantics() {
        let allowlist: Set<String> = ["bit.ly"]

        XCTAssertFalse(ShortlinkResolver.isConfiguredShortlinkHost(
            "links.bit.ly", allowlist: allowlist, mode: .exactHostHTTPAndHTTPS))
        XCTAssertTrue(ShortlinkResolver.isConfiguredShortlinkHost(
            "links.bit.ly", allowlist: allowlist, mode: .domainSuffixHTTPAndHTTPS))
        XCTAssertFalse(ShortlinkResolver.isConfiguredShortlinkHost(
            "evilbit.ly", allowlist: allowlist, mode: .domainSuffixHTTPAndHTTPS))
        XCTAssertFalse(ShortlinkResolver.isConfiguredShortlinkURL(
            URL(string: "http://bit.ly/a")!,
            allowlist: allowlist,
            mode: .exactHostHTTPS))
        XCTAssertTrue(ShortlinkResolver.isConfiguredShortlinkURL(
            URL(string: "https://bit.ly/a")!,
            allowlist: allowlist,
            mode: .exactHostHTTPS))
    }

    func testResolverLogURLRemovesCredentialsPathAndQuery() {
        let url = URL(
            string: "https://user:secret@bit.ly/private?auth_token=secret#callback")!

        XCTAssertEqual(ShortlinkResolver.redactedLogURL(url), "https://bit.ly")
    }

    func testPinnedTransportKeepsTheOriginalHostAndValidatedAddress() throws {
        var request = URLRequest(url: URL(string: "https://bit.ly/path")!)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2.5

        let arguments = try PinnedCurlTransport.arguments(
            for: request,
            pinnedAddresses: ["1.1.1.1", "8.8.8.8"])

        XCTAssertTrue(arguments.contains("bit.ly:443:1.1.1.1,8.8.8.8"))
        XCTAssertTrue(arguments.contains("--head"))
        XCTAssertTrue(arguments.contains("--noproxy"))
        XCTAssertTrue(arguments.contains("=http,https"))
        XCTAssertEqual(arguments.suffix(2), ["--config", "-"])
        XCTAssertFalse(arguments.contains { $0.contains("/path") })
    }

    func testPinnedTransportGETDiscardsTheBodyAndRequestsOneByte() throws {
        var request = URLRequest(url: URL(string: "http://bit.ly/path")!)
        request.httpMethod = "GET"

        let arguments = try PinnedCurlTransport.arguments(
            for: request,
            pinnedAddresses: ["2606:4700:4700::1111"])

        XCTAssertTrue(arguments.contains("bit.ly:80:[2606:4700:4700::1111]"))
        XCTAssertTrue(arguments.contains("--range"))
        XCTAssertTrue(arguments.contains("0-0"))
        XCTAssertTrue(arguments.contains("/dev/null"))
    }

    func testNetworkSafetyRejectsNonGlobalIPv4Addresses() {
        let privateAddresses: [[UInt8]] = [
            [0, 0, 0, 0],
            [10, 0, 0, 1],
            [100, 64, 0, 1],
            [127, 0, 0, 1],
            [169, 254, 1, 1],
            [172, 16, 0, 1],
            [192, 168, 0, 1],
            [198, 18, 0, 1],
            [224, 0, 0, 1],
        ]
        for address in privateAddresses {
            XCTAssertFalse(NetworkHostSafety.isPublicAddress(address), "\(address)")
        }

        XCTAssertTrue(NetworkHostSafety.isPublicAddress([1, 1, 1, 1]))
    }

    func testNetworkSafetyRejectsNonGlobalAndEmbeddedIPv6Addresses() {
        let loopback = [UInt8](repeating: 0, count: 15) + [1]
        let uniqueLocal = [0xfd] + [UInt8](repeating: 0, count: 15)
        let mappedPrivate = [UInt8](repeating: 0, count: 10)
            + [0xff, 0xff, 192, 168, 1, 1]
        let sixToFourPrivate = [0x20, 0x02, 10, 0, 0, 1]
            + [UInt8](repeating: 0, count: 10)
        let teredo = [0x20, 0x01, 0x00, 0x00]
            + [UInt8](repeating: 0, count: 12)
        let benchmarking = [0x20, 0x01, 0x00, 0x02]
            + [UInt8](repeating: 0, count: 12)
        let orchid = [0x20, 0x01, 0x00, 0x20]
            + [UInt8](repeating: 0, count: 12)
        let documentation = [0x3f, 0xff, 0x00, 0x00]
            + [UInt8](repeating: 0, count: 12)
        let publicAddress: [UInt8] = [
            0x26, 0x06, 0x47, 0x00, 0x47, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11, 0x11,
        ]

        XCTAssertFalse(NetworkHostSafety.isPublicAddress(loopback))
        XCTAssertFalse(NetworkHostSafety.isPublicAddress(uniqueLocal))
        XCTAssertFalse(NetworkHostSafety.isPublicAddress(mappedPrivate))
        XCTAssertFalse(NetworkHostSafety.isPublicAddress(sixToFourPrivate))
        XCTAssertFalse(NetworkHostSafety.isPublicAddress(teredo))
        XCTAssertFalse(NetworkHostSafety.isPublicAddress(benchmarking))
        XCTAssertFalse(NetworkHostSafety.isPublicAddress(orchid))
        XCTAssertFalse(NetworkHostSafety.isPublicAddress(documentation))
        XCTAssertTrue(NetworkHostSafety.isPublicAddress(publicAddress))
    }

    func testResolverStopsBeforeRequestForUnsafeResolvedHost() async {
        let resolver = ShortlinkResolver(hostIsPublic: { _ in false })
        let input = URL(string: "https://user:secret@bit.ly/private")!

        let result = await resolver.resolve(input)

        XCTAssertEqual(result.absoluteString, "https://bit.ly/private")
    }

    func testOffAllowlistRedirectReturnsWithoutDNSOrSecondRequest() async throws {
        let log = ShortlinkTestLog()
        let resolver = ShortlinkResolver(
            hostIsPublic: { host in
                await log.addDNS(host)
                return true
            },
            responseLoader: { request, _ in
                await log.addRequest(request.url!)
                return HTTPURLResponse(
                    url: request.url!,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "https://example.com/final"])!
            })

        let result = await resolver.resolve(
            URL(string: "https://bit.ly/start")!,
            allowlist: ["bit.ly"],
            mode: .exactHostHTTPAndHTTPS)

        XCTAssertEqual(result.absoluteString, "https://example.com/final")
        let values = await log.values()
        XCTAssertEqual(values.dns, ["bit.ly"])
        XCTAssertEqual(values.requests.map(\.host), ["bit.ly"])
    }

    func testUnsafeOffAllowlistRedirectReturnsOriginal() async {
        let resolver = ShortlinkResolver(
            hostIsPublic: { _ in true },
            responseLoader: { request, _ in
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "http://127.0.0.1/admin"])!
            })
        let input = URL(string: "https://bit.ly/start")!

        let result = await resolver.resolve(input, allowlist: ["bit.ly"])

        XCTAssertEqual(result, input)
    }

    func testStatus305IsNotTreatedAsARedirect() async {
        let log = ShortlinkTestLog()
        let resolver = ShortlinkResolver(
            hostIsPublic: { _ in true },
            responseLoader: { request, _ in
                await log.addRequest(request.url!)
                return HTTPURLResponse(
                    url: request.url!,
                    statusCode: 305,
                    httpVersion: nil,
                    headerFields: ["Location": "https://example.com/proxy"])!
            })
        let input = URL(string: "https://bit.ly/start")!

        let result = await resolver.resolve(input, allowlist: ["bit.ly"])

        XCTAssertEqual(result, input)
        let values = await log.values()
        XCTAssertEqual(values.requests.count, 1)
    }

    func testTimeoutIncludesAHostSafetyCheckThatIgnoresCancellation() async {
        let resolver = ShortlinkResolver(hostIsPublic: { _ in
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    continuation.resume(returning: true)
                }
            }
        })
        let input = URL(string: "https://bit.ly/start")!
        let started = Date()

        let result = await resolver.resolve(input, timeout: 0.03)

        XCTAssertEqual(result, input)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.3)
    }

    func testCancellationStopsAHostSafetyCheckBeforeTheDeadline() async {
        let resolver = ShortlinkResolver(hostIsPublic: { _ in
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                    continuation.resume(returning: true)
                }
            }
        })
        let input = URL(string: "https://bit.ly/start")!
        let task = Task { await resolver.resolve(input, timeout: 3) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        let started = Date()

        task.cancel()
        let result = await task.value

        XCTAssertEqual(result, input)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.3)
    }

    func testCancelledRequestDoesNotCacheTheUnresolvedURL() async {
        let attempts = ShortlinkAttemptCounter()
        let resolver = ShortlinkResolver(
            hostIsPublic: { _ in true },
            responseLoader: { request, _ in
                if await attempts.next() == 1 {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                }
                return HTTPURLResponse(
                    url: request.url!,
                    statusCode: 302,
                    httpVersion: nil,
                    headerFields: ["Location": "https://example.com/final"])!
            })
        let input = URL(string: "https://bit.ly/start")!
        let first = Task { await resolver.resolve(input, allowlist: ["bit.ly"]) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        first.cancel()
        _ = await first.value

        let second = await resolver.resolve(input, allowlist: ["bit.ly"])
        let attemptCount = await attempts.value()

        XCTAssertEqual(second.absoluteString, "https://example.com/final")
        XCTAssertEqual(attemptCount, 2)
    }

    func testTimeoutCoversTheWholeResolution() async {
        let resolver = ShortlinkResolver(
            hostIsPublic: { _ in true },
            responseLoader: { _, _ in
                try await Task.sleep(nanoseconds: 1_000_000_000)
                throw URLError(.timedOut)
            })
        let input = URL(string: "https://bit.ly/start")!
        let started = Date()

        let result = await resolver.resolve(input, timeout: 0.03)

        XCTAssertEqual(result, input)
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.3)
    }
}

private actor ShortlinkTestLog {
    private var dns: [String] = []
    private var requests: [URL] = []

    func addDNS(_ host: String) { dns.append(host) }
    func addRequest(_ url: URL) { requests.append(url) }
    func values() -> (dns: [String], requests: [URL]) { (dns, requests) }
}

private actor ShortlinkAttemptCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
    }

    func value() -> Int { count }
}
