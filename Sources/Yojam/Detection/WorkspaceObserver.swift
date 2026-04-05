import AppKit

@MainActor
final class WorkspaceObserver {
    private let reconciler: ChangeReconciler
    private var launchObserver: NSObjectProtocol?
    // §54: Debounce rapid app launch notifications (e.g. at login)
    private let debouncer = Debouncer(delay: 1.0)

    init(reconciler: ChangeReconciler) { self.reconciler = reconciler }

    func startObserving() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // §54: Debounce into a full reconcile to avoid flooding at login
                self?.debouncer.debounce {
                    self?.reconciler.reconcile()
                }
            }
        }
    }

    func stopObserving() {
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}
