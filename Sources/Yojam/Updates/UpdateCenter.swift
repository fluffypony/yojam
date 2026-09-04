import AppKit
import Combine
import Sparkle
import UserNotifications

/// Owns Sparkle and turns its scheduled update alerts into reminders a menu
/// bar app can surface.
///
/// Sparkle 2.2 and later never lets a scheduled update alert steal focus from
/// a dockless app. It orders the alert behind every other window, where
/// nobody sees it, so Yojam users fell releases behind without knowing
/// (issue #38). Sparkle's gentle-reminder hooks let Yojam take over instead:
/// a dot on the menu bar icon, an entry at the top of its menu, an Install
/// button in Preferences, and a notification. Sparkle still shows its own
/// alert when it can put it in front properly, which is an overdue check
/// right after launch, and for every check the user starts.
@MainActor
final class UpdateCenter: NSObject, ObservableObject {
    struct AvailableUpdate: Equatable, Sendable {
        /// User-facing version, for example "1.2.4".
        let version: String
        /// Build number Sparkle compares, for example "14".
        let build: String
    }

    /// A newer build Sparkle has found and the user has not acted on yet.
    @Published private(set) var availableUpdate: AvailableUpdate?
    /// True while a check the user started is talking to yoj.am.
    @Published private(set) var isChecking = false
    @Published private(set) var lastCheckDate: Date?
    /// True when the last check could not load the appcast.
    @Published private(set) var lastCheckFailed = false

    nonisolated static let notificationIdentifier = "com.yojam.update-available"
    private static let lastNotifiedBuildKey = "updateCenterLastNotifiedBuild"

    private(set) var updaterController: SPUStandardUpdaterController!
    var updater: SPUUpdater { updaterController.updater }

    private let defaults: UserDefaults
    /// UNUserNotificationCenter aborts in a process without an app bundle,
    /// such as `swift run`, so notifications stay off there.
    private let isBundledApp: Bool
    private var hasStarted = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.isBundledApp = Bundle.main.bundleURL.pathExtension == "app"
        super.init()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self)
    }

    var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var installedBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }

    /// Sparkle persists this itself; the setter only announces the change so
    /// SwiftUI re-reads it.
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// Starts Sparkle's update cycle. Call once the app has finished launching.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if isBundledApp {
            UNUserNotificationCenter.current().delegate = self
        }
        updaterController.startUpdater()
        lastCheckDate = updater.lastUpdateCheckDate
    }

    /// A user-initiated check. When an update is already waiting this brings
    /// Sparkle's alert for it to the front instead of checking again.
    func checkForUpdates() {
        guard hasStarted else { return }
        if availableUpdate == nil, updater.canCheckForUpdates {
            isChecking = true
            lastCheckFailed = false
        }
        updater.checkForUpdates()
    }

    /// - Parameter includesVersion: false where the installed version is
    ///   already on screen, as on the About tab.
    func statusText(now: Date = Date(), includesVersion: Bool = true) -> String {
        Self.statusText(
            installedVersion: installedVersion,
            installedBuild: installedBuild,
            availableUpdate: availableUpdate,
            isChecking: isChecking,
            lastCheckFailed: lastCheckFailed,
            lastCheckDate: lastCheckDate,
            now: now,
            includesVersion: includesVersion)
    }

    nonisolated static func statusText(
        installedVersion: String,
        installedBuild: String,
        availableUpdate: AvailableUpdate?,
        isChecking: Bool,
        lastCheckFailed: Bool,
        lastCheckDate: Date?,
        now: Date = Date(),
        includesVersion: Bool = true
    ) -> String {
        if isChecking {
            return "Checking yoj.am for a new version\u{2026}"
        }
        if let availableUpdate {
            return "Yojam \(availableUpdate.version) is ready to install. You have \(installedVersion)."
        }
        let prefix = includesVersion ? "Version \(installedVersion) (\(installedBuild)) \u{00B7} " : ""
        if lastCheckFailed {
            return prefix + "Couldn't reach yoj.am on the last check"
        }
        guard let lastCheckDate else {
            return prefix + "Not checked yet"
        }
        return prefix + "Last checked \(relativeDescription(of: lastCheckDate, now: now))"
    }

    nonisolated static func relativeDescription(of date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    // MARK: - Reminders

    private func noteAvailableUpdate(
        _ update: AvailableUpdate,
        sparkleShowsAlert: Bool,
        userInitiated: Bool
    ) {
        isChecking = false
        lastCheckFailed = false
        availableUpdate = update
        // Sparkle's own alert, or one the user asked for, needs no extra nudge.
        guard !userInitiated, !sparkleShowsAlert else { return }
        postNotificationOncePerBuild(for: update)
    }

    /// One notification per build, so a user who chose Remind Me Later is not
    /// pinged again on every hourly check. The menu bar dot returns quietly.
    private func postNotificationOncePerBuild(for update: AvailableUpdate) {
        guard isBundledApp else { return }
        guard defaults.string(forKey: Self.lastNotifiedBuildKey) != update.build else { return }
        defaults.set(update.build, forKey: Self.lastNotifiedBuildKey)

        let title = "Yojam \(update.version) is available"
        let body = "Click to see what changed and install it."
        Task {
            let center = UNUserNotificationCenter.current()
            // Asked here, when there is something to say, rather than at launch.
            let granted = (try? await center.requestAuthorization(options: [.alert])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier, content: content, trigger: nil)
            try? await center.add(request)
        }
    }

    private func removeDeliveredNotification() {
        guard isBundledApp else { return }
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    nonisolated private static func isBenign(_ error: any Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain else { return false }
        return nsError.code == Int(SUError.noUpdateError.rawValue)
            || nsError.code == Int(SUError.installationCanceledError.rawValue)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateCenter: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        isChecking = false
        lastCheckFailed = false
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        isChecking = false
        lastCheckFailed = false
        availableUpdate = nil
        lastCheckDate = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        isChecking = false
        lastCheckDate = updater.lastUpdateCheckDate
        if !Self.isBenign(error) {
            lastCheckFailed = true
            YojamLogger.shared.log("Update check failed: \(error.localizedDescription)")
        }
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        isChecking = false
        lastCheckDate = updater.lastUpdateCheckDate
    }
}

// MARK: - SPUStandardUserDriverDelegate (gentle reminders)

extension UpdateCenter: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle asks before it presents a scheduled update. It may show the
    /// alert itself only when it can bring it to the front (an overdue check
    /// right after launch). Otherwise Yojam reminds gently.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        let found = AvailableUpdate(version: update.displayVersionString, build: update.versionString)
        let userInitiated = state.userInitiated
        // Sparkle's standard driver calls its delegate on the main thread.
        MainActor.assumeIsolated {
            noteAvailableUpdate(
                found, sparkleShowsAlert: handleShowingUpdate, userInitiated: userInitiated)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { removeDeliveredNotification() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            availableUpdate = nil
            removeDeliveredNotification()
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension UpdateCenter: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        guard identifier == Self.notificationIdentifier,
              action == UNNotificationDefaultActionIdentifier else { return }
        await MainActor.run { self.checkForUpdates() }
    }
}
