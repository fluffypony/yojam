import Foundation

/// The outcome of the routing decision engine. AppDelegate executes
/// the chosen variant via app-only executors (picker, browser launcher, etc.).
public enum RouteDecision: Sendable, Equatable {
    /// Open the URL directly in a specific browser.
    case openDirect(browser: BrowserEntry, finalURL: URL, privateWindow: Bool, reason: String)

    /// Present the browser picker to the user.
    case showPicker(entries: [BrowserEntry], preselectedIndex: Int, finalURL: URL, isEmail: Bool, reason: String?)

    /// Routing is disabled or no browser is available. Open via the system default path.
    case openSystemDefault(URL)

    /// Hand the mailto URL to the system mail handler.
    case openSystemMailHandler(URL)
}
