import AppKit

@MainActor
final class WorkspaceObserver {
    private let reconciler: ChangeReconciler
    private var launchObserver: NSObjectProtocol?

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
                self?.reconciler.appDiscovered(
                    bundleId: bundleId, appURL: url)
            }
        }
    }

    func stopObserving() {
        if let obs = launchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
    }
}
