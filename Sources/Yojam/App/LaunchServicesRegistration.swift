import CoreServices
import Foundation

/// Refreshes Launch Services after an update changes Yojam's declared roles.
///
/// macOS normally discovers bundle changes through Finder or at login. An
/// explicit update keeps AuthenticationServices from using stale browser
/// capability data until the next restart.
enum LaunchServicesRegistration {
    typealias Register = (CFURL, Bool) -> OSStatus

    @discardableResult
    static func refresh(
        bundleURL: URL = Bundle.main.bundleURL,
        register: Register = LSRegisterURL
    ) -> OSStatus {
        register(bundleURL as CFURL, true)
    }
}
