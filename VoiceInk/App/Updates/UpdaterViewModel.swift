import SwiftUI
import os

/// This fork never runs Sparkle.
///
/// Upstream ships an appcast at beingpax.github.io pointing at Beingpax's own
/// releases, and the fork publishes no appcast of its own — so the only thing a
/// check can ever find is the vendor's build, which reinstates the license gate
/// and drops every fork feature. It happened once: on 29 July Sparkle installed
/// the signed 2.1 DMG over /Applications/VoiceInk.app. The updater is therefore
/// a deliberately inert shim with upstream's shape; updating this fork means
/// pulling and running `make local-stable`.
@MainActor
final class UpdaterViewModel: ObservableObject {
    struct AvailableUpdate: Equatable {
        let versionIdentifier: String
        let displayVersion: String
    }

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "updates")

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var checksForUpdatesWhenDashboardAppears = false
    @Published private(set) var availableUpdate: AvailableUpdate?

    func setAutomaticallyChecksForUpdates(_ value: Bool) {
        logger.notice("Update check ignored reason=fork-build-has-no-appcast")
    }

    func setChecksForUpdatesWhenDashboardAppears(_ value: Bool) {
        logger.notice("Update check ignored reason=fork-build-has-no-appcast")
    }

    func checkForUpdatesIfDue() {
        logger.notice("Update check ignored reason=fork-build-has-no-appcast")
    }

    func checkForUpdates() {
        logger.notice("Update check ignored reason=fork-build-has-no-appcast")
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
