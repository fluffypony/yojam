import AppKit

@MainActor
final class WorkspaceObserver {
    private let reconciler: ChangeReconciler
    private var launchObserver: NSObjectProtocol?
    // §54: Debounce reconciliation to avoid spam during login when many apps launch
    private let debouncer = Debouncer(delay: 1.0)

    init(reconciler: ChangeReconciler) { self.reconciler = reconciler }

    func startObserving() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[
                NSWorkspace.applicationUserInfoKey
            ] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier,
                  let url = app.bundleURL else { return }
            Task { @MainActor in
                guard let self else { return }
                self.debouncer.debounce {
                    self.reconciler.appDiscovered(
                        bundleId: bundleId, appURL: url)
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
