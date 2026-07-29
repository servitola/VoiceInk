import SwiftUI

@MainActor
final class UpdaterViewModel: ObservableObject {
    struct AvailableUpdate: Equatable {
        let versionIdentifier: String
        let displayVersion: String
    }

    @Published var canCheckForUpdates = false
    @Published private(set) var checksForUpdatesWhenDashboardAppears = false
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published var automaticallyChecksForUpdates = false

    func setChecksForUpdatesWhenDashboardAppears(_ value: Bool) {}

    func checkForUpdatesIfDue() {}

    func setAutomaticallyChecksForUpdates(_ value: Bool) {}

    func checkForUpdates() {}
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}
