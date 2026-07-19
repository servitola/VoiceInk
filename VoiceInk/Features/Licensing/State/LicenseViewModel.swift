import Foundation
import AppKit
import os

@MainActor
class LicenseViewModel: ObservableObject {
    enum LicenseState: Equatable {
        case unlicensed
        case trial(daysRemaining: Int)
        case trialExpired
        case licensed
    }

    @Published private(set) var licenseState: LicenseState = .licensed
    @Published var licenseKey: String = ""
    @Published var isValidating = false
    @Published var validationMessage: String?
    @Published var validationSuccess: Bool = false
    @Published private(set) var isDeactivating = false
    @Published private(set) var activationsLimit: Int = 999

    static let shared = LicenseViewModel()

    init() {
        // Always licensed for free fork
        licenseState = .licensed
    }

    var hasVerifiedLicense: Bool { true }

    @discardableResult
    func startTrial() -> Bool {
        // No trial to start: the free fork is already licensed.
        true
    }

    func validateLicense(_ licenseKey: String = "") async {
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

    func refreshLicenseState() {
        // Always licensed for free fork
        licenseState = .licensed
    }

    var diagnosticLicenseStatus: String { "Licensed (free fork)" }

    var usageRestrictionMessage: String? {
        // Free fork: never restrict usage
        return nil
    }

    func openPurchaseLink() {
        if let url = URL(string: "https://tryvoiceink.com/buy") {
            NSWorkspace.shared.open(url)
        }
    }

    func removeLicense() {
        // No-op for free version
    }
}
