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

    // §41: Invalidate timer if object is deallocated without calling stop()
    deinit {
        let t = timer
        if Thread.isMainThread {
            t?.invalidate()
        } else {
            DispatchQueue.main.async { t?.invalidate() }
        }
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
}
