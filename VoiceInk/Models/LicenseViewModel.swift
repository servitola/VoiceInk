import Foundation
import AppKit
import os

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var activationsLimit: Int = 999

    init() {
        // Always licensed for free fork
        licenseState = .licensed
    }

    func startTrial() {
        // No-op for free version
    }

    func validateLicense() async {
        // Always valid for free version
        licenseState = .licensed
        validationSuccess = true
    }

    func deactivateLicense() async {
        // No-op for free version
    }

    func revalidateLicense() {
        // No-op for free version
    }

    func checkLicenseStatus() {
        // Always licensed
        licenseState = .licensed
    }

    func removeLicense() {
        // No-op for free version
    }
}
