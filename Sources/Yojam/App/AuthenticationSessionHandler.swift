import AuthenticationServices
import Foundation
import YojamCore

private final class AuthenticationSessionRequestState: @unchecked Sendable {
    private struct Entry {
        var beginIsPending = false
        var isCancelled = false
        var request: ASWebAuthenticationSessionRequest?
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]

    func recordBegin(id: UUID, request: ASWebAuthenticationSessionRequest?) {
        lock.lock()
        defer { lock.unlock() }

        var entry = entries[id] ?? Entry()
        entry.beginIsPending = true
        entry.request = request
        entries[id] = entry
    }

    func recordCancellation(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        var entry = entries[id] ?? Entry()
        entry.isCancelled = true
        entries[id] = entry
    }

    func takeRouteDecision(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard var entry = entries[id], entry.beginIsPending else { return false }
        entry.beginIsPending = false
        guard !entry.isCancelled else {
            entries.removeValue(forKey: id)
            return false
        }

        if entry.request == nil {
            entries.removeValue(forKey: id)
        } else {
            entries[id] = entry
        }
        return true
    }

    func finishCancellation(id: UUID) {
        lock.lock()
        defer { lock.unlock() }

        guard entries[id]?.beginIsPending != true else { return }
        entries.removeValue(forKey: id)
    }

    func takeRequest(id: UUID) -> ASWebAuthenticationSessionRequest? {
        lock.lock()
        defer { lock.unlock() }

        guard let entry = entries.removeValue(forKey: id), !entry.isCancelled else {
            return nil
        }
        return entry.request
    }
}

/// Receives sign-in requests that macOS sends through AuthenticationServices.
@MainActor
final class AuthenticationSessionHandler: NSObject,
    ASWebAuthenticationSessionWebBrowserSessionHandling {
    nonisolated static let requestIDMetadataKey = "authenticationSessionID"

    private let onRequest: @MainActor @Sendable (UUID, IncomingLinkRequest) -> Void
    private let onCancel: @MainActor @Sendable (UUID) -> Void
    nonisolated private let requestState = AuthenticationSessionRequestState()

    init(
        onRequest: @escaping @MainActor @Sendable (UUID, IncomingLinkRequest) -> Void,
        onCancel: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        self.onRequest = onRequest
        self.onCancel = onCancel
        super.init()
    }

    func install() -> Bool {
        let manager = ASWebAuthenticationSessionWebBrowserSessionManager.shared
        manager.sessionHandler = self
        return manager.wasLaunchedByAuthenticationServices
    }

    nonisolated func begin(_ request: ASWebAuthenticationSessionRequest) {
        forward(id: request.uuid, url: request.url, request: request)
    }

    nonisolated func cancel(_ request: ASWebAuthenticationSessionRequest) {
        forwardCancellation(id: request.uuid)
    }

    /// AuthenticationServices invokes its handler on a worker thread.
    /// Move routing state and AppKit work onto the main queue.
    nonisolated func forward(id: UUID, url: URL) {
        forward(id: id, url: url, request: nil)
    }

    private nonisolated func forward(
        id: UUID,
        url: URL,
        request: ASWebAuthenticationSessionRequest?
    ) {
        requestState.recordBegin(id: id, request: request)
        DispatchQueue.main.async { [weak self] in
            guard let self, self.requestState.takeRouteDecision(id: id) else { return }
            self.onRequest(id, Self.makeIncomingRequest(id: id, url: url))
        }
    }

    nonisolated func forwardCancellation(id: UUID) {
        requestState.recordCancellation(id: id)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onCancel(id)
            self.requestState.finishCancellation(id: id)
        }
    }

    func cancelSourceRequest(id: UUID) {
        guard let request = requestState.takeRequest(id: id) else { return }
        let error = NSError(
            domain: ASWebAuthenticationSessionError.errorDomain,
            code: ASWebAuthenticationSessionError.Code.canceledLogin.rawValue)
        request.cancelWithError(error)
    }

    func discardSourceRequest(id: UUID) {
        _ = requestState.takeRequest(id: id)
    }

    nonisolated static func makeIncomingRequest(id: UUID, url: URL) -> IncomingLinkRequest {
        IncomingLinkRequest(
            url: url,
            sourceAppBundleId: SourceAppSentinel.authenticationSession,
            origin: .authenticationSession,
            metadata: [requestIDMetadataKey: id.uuidString])
    }
}
