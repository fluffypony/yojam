import Foundation
import CoreServices

@MainActor
final class AppInstallMonitor {
    private let reconciler: ChangeReconciler
    private var stream: FSEventStreamRef?
    private let debouncer = Debouncer(delay: 0.5)
    private let watchedPaths = [
        "/Applications",
        NSHomeDirectory() + "/Applications",
        "/Applications/Setapp",
    ]

    init(reconciler: ChangeReconciler) { self.reconciler = reconciler }

    func startMonitoring() {
        let pathsCF = watchedPaths as CFArray
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = {
            _, clientInfo, _, eventPaths, _, _ in
            guard let clientInfo else { return }
            // §44: Safe cast instead of force-cast
            guard let paths = Unmanaged<CFArray>
                .fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
            let appPaths = paths.filter {
                $0.hasSuffix(".app") || $0.contains(".app/")
            }
            if !appPaths.isEmpty {
                // Stream dispatches on .main, so MainActor.assumeIsolated is safe
                let monitor = Unmanaged<AppInstallMonitor>
                    .fromOpaque(clientInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    monitor.debouncer.debounce {
                        monitor.reconciler.reconcile()
                    }
                }
            }
        }

        stream = FSEventStreamCreate(
            nil, callback, &context, pathsCF,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            UInt32(kFSEventStreamCreateFlagUseCFTypes
                   | kFSEventStreamCreateFlagFileEvents))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            FSEventStreamStart(stream)
        }
    }

    func stopMonitoring() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
