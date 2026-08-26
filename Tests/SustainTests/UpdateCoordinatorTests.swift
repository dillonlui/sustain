import Foundation
import Testing
@testable import Sustain

@MainActor
private final class FakeUpdateDriver: UpdateChecking {
    var automaticallyChecksForUpdates = false
    var manualChecks = 0
    var backgroundChecks = 0

    func checkForUpdates() { manualChecks += 1 }
    func checkForUpdatesInBackground() { backgroundChecks += 1 }
}

@MainActor
@Suite("Native update coordination")
struct UpdateCoordinatorTests {
    private var eligibleInfo: [String: Any] {
        [
            "SustainOfficialStableUpdatesEnabled": true,
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42",
            "SUFeedURL": "https://updates.example.test/appcast.xml",
            "SUPublicEDKey": "test-public-key"
        ]
    }

    @Test func eligibilityRequiresExplicitStableDeveloperIDConfiguration() {
        #expect(UpdateBuildEligibility.evaluate(
            info: eligibleInfo,
            hasValidDeveloperIDSignature: true
        ) == .eligible)

        var info = eligibleInfo
        info["SustainOfficialStableUpdatesEnabled"] = false
        #expect(!UpdateBuildEligibility.evaluate(
            info: info,
            hasValidDeveloperIDSignature: true
        ).isEligible)
        #expect(!UpdateBuildEligibility.evaluate(
            info: eligibleInfo,
            hasValidDeveloperIDSignature: false
        ).isEligible)

        info = eligibleInfo
        info["CFBundleShortVersionString"] = "1.2.3-beta.1"
        #expect(!UpdateBuildEligibility.evaluate(
            info: info,
            hasValidDeveloperIDSignature: true
        ).isEligible)

        info = eligibleInfo
        info["SUFeedURL"] = "http://updates.example.test/appcast.xml"
        #expect(!UpdateBuildEligibility.evaluate(
            info: info,
            hasValidDeveloperIDSignature: true
        ).isEligible)
    }

    @Test func manualChecksRunImmediatelyOnlyWhenIdle() {
        let driver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(
            eligibility: .eligible,
            driver: driver,
            isAudioActive: { false },
            flushPersistence: { true }
        )

        coordinator.requestManualCheck()

        #expect(driver.manualChecks == 1)
        #expect(driver.backgroundChecks == 0)
        #expect(!coordinator.hasDeferredCheck)
    }

    @Test func activeAudioCoalescesManualAndDelegateChecksThenReleasesOnce() throws {
        final class State { var audioActive = true }
        let state = State()
        let driver = FakeUpdateDriver()
        var statuses: [String] = []
        let coordinator = UpdateCoordinator(
            eligibility: .eligible,
            driver: driver,
            isAudioActive: { state.audioActive },
            flushPersistence: { true },
            statusSink: { statuses.append($0) }
        )

        coordinator.requestManualCheck()
        coordinator.requestManualCheck()
        #expect(throws: (any Error).self) { try coordinator.allowCheck(.background) }
        #expect(coordinator.hasDeferredCheck)
        #expect(driver.manualChecks == 0)

        state.audioActive = false
        coordinator.audioActivityDidChange()
        coordinator.audioActivityDidChange()

        #expect(driver.backgroundChecks == 1)
        #expect(!coordinator.hasDeferredCheck)
        #expect(statuses.contains("Update check deferred until playback stops"))
    }

    @Test func readOnlyVolumeDefersBackgroundWithoutContactingFeed() {
        let driver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(
            eligibility: .eligible,
            driver: driver,
            isAudioActive: { false },
            flushPersistence: { true },
            isReadOnlyVolume: { _ in true }
        )

        #expect(throws: (any Error).self) { try coordinator.allowCheck(.background) }

        #expect(coordinator.hasDeferredCheck)
        #expect(driver.backgroundChecks == 0)
        coordinator.audioActivityDidChange()
        #expect(driver.backgroundChecks == 0)
    }

    @Test func relaunchWaitsForIdleAndInvokesOneHandlerOnce() {
        final class State { var audioActive = true; var installs = 0 }
        let state = State()
        let driver = FakeUpdateDriver()
        var flushes = 0
        let coordinator = UpdateCoordinator(
            eligibility: .eligible,
            driver: driver,
            isAudioActive: { state.audioActive },
            flushPersistence: { flushes += 1; return true }
        )

        #expect(coordinator.postponeRelaunch { state.installs += 1 })
        #expect(coordinator.hasDeferredRelaunch)
        #expect(state.installs == 0)

        state.audioActive = false
        coordinator.audioActivityDidChange()
        coordinator.audioActivityDidChange()

        #expect(flushes == 1)
        #expect(state.installs == 1)
        #expect(!coordinator.hasDeferredRelaunch)
    }

    @Test func saveFailureKeepsAppRunningUntilPersistenceRecovers() {
        final class State { var saveSucceeds = false; var installs = 0 }
        let state = State()
        let driver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(
            eligibility: .eligible,
            driver: driver,
            isAudioActive: { false },
            flushPersistence: { state.saveSucceeds }
        )

        #expect(coordinator.postponeRelaunch { state.installs += 1 })
        coordinator.persistenceDidRecover()
        #expect(state.installs == 0)
        #expect(coordinator.hasDeferredRelaunch)

        state.saveSucceeds = true
        coordinator.persistenceDidRecover()

        #expect(state.installs == 1)
        #expect(!coordinator.hasDeferredRelaunch)
    }

    @Test func automaticCheckPreferenceUsesSparklesAuthority() {
        let driver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(
            eligibility: .eligible,
            driver: driver,
            isAudioActive: { false },
            flushPersistence: { true }
        )

        coordinator.automaticallyChecksForUpdates = true

        #expect(driver.automaticallyChecksForUpdates)
        #expect(coordinator.automaticallyChecksForUpdates)
    }

    @Test func onlyManualErrorsBecomeAppOwnedStatus() {
        let driver = FakeUpdateDriver()
        let coordinator = UpdateCoordinator(
            eligibility: .eligible,
            driver: driver,
            isAudioActive: { false },
            flushPersistence: { true }
        )
        let error = NSError(
            domain: "test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "No update is available"]
        )

        coordinator.finishUpdateCycle(kind: .background, error: error)
        #expect(coordinator.statusMessage == nil)
        coordinator.finishUpdateCycle(kind: .manual, error: error)
        #expect(coordinator.statusMessage == "No update is available")
    }
}
