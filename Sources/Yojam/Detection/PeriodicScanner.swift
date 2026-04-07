import Foundation
import AppKit

@MainActor
final class PeriodicScanner {
    private let reconciler: ChangeReconciler
    private let interval: TimeInterval
    private var timer: Timer?

    init(reconciler: ChangeReconciler, interval: TimeInterval) {
        self.reconciler = reconciler; self.interval = interval
    }

    // Rely on explicit stop() calls from applicationWillTerminate and
    // config-change sinks. Removed deinit timer invalidation because
    // MainActor.assumeIsolated traps in Swift 6 strict concurrency
    // when deinit runs off the main actor.

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.reconciler.reconcile() }
        }
        reconciler.reconcile()
    }

    func stop() { timer?.invalidate(); timer = nil }
}
