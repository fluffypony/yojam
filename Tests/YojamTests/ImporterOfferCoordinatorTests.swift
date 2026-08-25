import XCTest
@testable import Yojam
import YojamCore

@MainActor
final class ImporterOfferCoordinatorTests: XCTestCase {
    func testIncompleteOfferDiscoversAndOrdersSources() {
        let coordinator = ImporterOfferCoordinator(currentVersion: 1) {
            [.finicky, .bumpr, .finicky]
        }

        coordinator.discoverIfNeeded(completedVersion: 0)

        XCTAssertEqual(coordinator.state, .available([.bumpr, .finicky]))
        XCTAssertEqual(
            coordinator.offerLabel,
            "Import from Bumpr or Finicky")
    }

    func testCompletedOfferDoesNotRunDiscovery() {
        var discoveryCount = 0
        let coordinator = ImporterOfferCoordinator(currentVersion: 3) {
            discoveryCount += 1
            return [.finicky]
        }

        coordinator.discoverIfNeeded(completedVersion: 3)

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertEqual(discoveryCount, 0)
    }

    func testNoDetectedSourcesMakesOfferUnavailable() {
        let coordinator = ImporterOfferCoordinator(currentVersion: 1) { [] }

        coordinator.discoverIfNeeded(completedVersion: 0)

        XCTAssertEqual(coordinator.state, .unavailable)
        XCTAssertNil(coordinator.offerLabel)
    }

    func testDiscoveryRunsOnlyOnce() {
        var discoveryCount = 0
        let coordinator = ImporterOfferCoordinator(currentVersion: 1) {
            discoveryCount += 1
            return [.choosy]
        }

        coordinator.discoverIfNeeded(completedVersion: 0)
        coordinator.discoverIfNeeded(completedVersion: 0)

        XCTAssertEqual(discoveryCount, 1)
        XCTAssertEqual(coordinator.state, .available([.choosy]))
    }

    func testSourceListNamesEveryDetectedApp() {
        XCTAssertEqual(ImporterOfferCoordinator.sourceList([]), "")
        XCTAssertEqual(ImporterOfferCoordinator.sourceList([.finicky]), "Finicky")
        XCTAssertEqual(
            ImporterOfferCoordinator.sourceList([.bumpr, .finicky]),
            "Bumpr or Finicky")
        XCTAssertEqual(
            ImporterOfferCoordinator.sourceList([.bumpr, .choosy, .finicky]),
            "Bumpr, Choosy, or Finicky")
    }

    func testMarkCompletedRemovesTheOffer() {
        let coordinator = ImporterOfferCoordinator(currentVersion: 1) {
            [.finicky]
        }
        coordinator.discoverIfNeeded(completedVersion: 0)

        coordinator.markCompleted()

        XCTAssertEqual(coordinator.state, .completed)
        XCTAssertNil(coordinator.offerLabel)
    }

    func testCancelLeavesTheOfferAvailable() {
        let coordinator = ImporterOfferCoordinator(currentVersion: 1) {
            [.finicky]
        }
        coordinator.discoverIfNeeded(completedVersion: 0)

        XCTAssertEqual(coordinator.state, .available([.finicky]))
    }
}

@MainActor
final class ImporterOfferPersistenceTests: XCTestCase {
    func testCurrentOfferCompletionPersists() throws {
        let suiteName = "ImporterOfferPersistenceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        XCTAssertFalse(store.hasCompletedCurrentImporterOffer)

        store.completeCurrentImporterOffer()

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.hasCompletedCurrentImporterOffer)
        XCTAssertEqual(
            reloaded.completedImporterOfferVersion,
            SettingsStore.currentImporterOfferVersion)
    }
}
