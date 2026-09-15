import XCTest
import YojamCore

class IsolatedRoutingTestCase: XCTestCase {
    let routingSuiteName = "org.yojam.core-tests.routing.\(UUID().uuidString)"

    func makeSharedStore() -> SharedRoutingStore {
        SharedRoutingStore(suiteName: routingSuiteName)
    }

    override func tearDown() {
        UserDefaults(suiteName: routingSuiteName)?.removePersistentDomain(forName: routingSuiteName)
        super.tearDown()
    }
}
