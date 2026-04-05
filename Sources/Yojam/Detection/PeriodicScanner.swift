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

    func start() {
        timer = Timer.scheduledTimer(
            withTimeInterval: interval, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.reconciler.reconcile() }
        }
        reconciler.reconcile()
    }

    func stop() { timer?.invalidate(); timer = nil }

    // §41: Clean up timer on deallocation
    deinit { timer?.invalidate() }
}
