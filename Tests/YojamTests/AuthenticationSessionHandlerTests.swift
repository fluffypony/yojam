import XCTest
@testable import Yojam
import YojamCore

final class AuthenticationSessionHandlerTests: XCTestCase {
    func testIncomingRequestUsesAuthenticationSource() throws {
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        let id = UUID()

        let request = AuthenticationSessionHandler.makeIncomingRequest(id: id, url: url)

        XCTAssertEqual(request.url, url)
        XCTAssertEqual(request.origin, .authenticationSession)
        XCTAssertEqual(
            request.sourceAppBundleId,
            SourceAppSentinel.authenticationSession)
        XCTAssertEqual(
            request.metadata[AuthenticationSessionHandler.requestIDMetadataKey],
            id.uuidString)
        XCTAssertFalse(request.forcePrivateWindow)
    }

    func testForwardMovesRequestToMainThread() async throws {
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        let id = UUID()
        let forwarded = expectation(description: "Request forwarded")
        let handler = await MainActor.run {
            AuthenticationSessionHandler(
                onRequest: { receivedID, request in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertEqual(receivedID, id)
                    XCTAssertEqual(request.url, url)
                    forwarded.fulfill()
                },
                onCancel: { _ in })
        }

        await Task.detached {
            handler.forward(id: id, url: url)
        }.value

        await fulfillment(of: [forwarded], timeout: 1)
    }

    func testCancellationMovesToMainThread() async {
        let id = UUID()
        let cancelled = expectation(description: "Cancellation forwarded")
        let handler = await MainActor.run {
            AuthenticationSessionHandler(
                onRequest: { _, _ in },
                onCancel: { receivedID in
                    XCTAssertTrue(Thread.isMainThread)
                    XCTAssertEqual(receivedID, id)
                    cancelled.fulfill()
                })
        }

        await Task.detached {
            handler.forwardCancellation(id: id)
        }.value

        await fulfillment(of: [cancelled], timeout: 1)
    }

    @MainActor
    func testCancellationBeforeMainQueueDrainPreventsForwarding() async throws {
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        let id = UUID()
        let forwarded = expectation(description: "Request not forwarded")
        forwarded.isInverted = true
        let cancelled = expectation(description: "Cancellation forwarded")
        let handler = AuthenticationSessionHandler(
            onRequest: { _, _ in forwarded.fulfill() },
            onCancel: { _ in cancelled.fulfill() })
        let workerFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            handler.forward(id: id, url: url)
            handler.forwardCancellation(id: id)
            workerFinished.signal()
        }

        XCTAssertEqual(workerFinished.wait(timeout: .now() + 1), .success)
        await fulfillment(of: [cancelled], timeout: 1)
        await fulfillment(of: [forwarded], timeout: 0.1)
    }

    func testAuthenticationSessionsHaveDistinctDeduplicationKeys() async throws {
        let url = try XCTUnwrap(URL(string: "https://accounts.example.com/sign-in"))
        let firstRequest = AuthenticationSessionHandler.makeIncomingRequest(
            id: UUID(),
            url: url)
        let secondRequest = AuthenticationSessionHandler.makeIncomingRequest(
            id: UUID(),
            url: url)

        let keys = await MainActor.run {
            (
                AppDelegate.routingDeduplicationKey(url: url, request: firstRequest),
                AppDelegate.routingDeduplicationKey(url: url, request: secondRequest)
            )
        }

        XCTAssertNotEqual(keys.0, keys.1)
    }
}
