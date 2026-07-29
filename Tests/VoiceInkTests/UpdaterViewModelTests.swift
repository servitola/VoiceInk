import Testing
@testable import VoiceInk

@MainActor
struct UpdaterViewModelTests {
    // Upstream's appcast once replaced this fork in /Applications with the
    // official release, restoring the license gate and removing fork features.
    @Test func aForkBuildNeverRunsSparkle() async {
        let updater = UpdaterViewModel()

        try? await Task.sleep(for: .milliseconds(500))

        #expect(updater.canCheckForUpdates == false)
        #expect(updater.checksForUpdatesWhenDashboardAppears == false)
        #expect(updater.availableUpdate == nil)
        #expect(updater.automaticallyChecksForUpdates == false)
    }

    @Test func askingForUpdatesDoesNothing() async {
        let updater = UpdaterViewModel()

        updater.checkForUpdates()
        updater.setChecksForUpdatesWhenDashboardAppears(true)
        updater.checkForUpdatesIfDue()
        updater.setAutomaticallyChecksForUpdates(true)
        try? await Task.sleep(for: .milliseconds(500))

        #expect(updater.canCheckForUpdates == false)
        #expect(updater.checksForUpdatesWhenDashboardAppears == false)
        #expect(updater.availableUpdate == nil)
        #expect(updater.automaticallyChecksForUpdates == false)
    }
}
