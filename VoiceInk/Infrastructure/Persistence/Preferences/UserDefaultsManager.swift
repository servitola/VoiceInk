import Foundation

extension UserDefaults {
    enum Keys {
        static let audioInputMode = "audioInputMode"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let selectedAudioDeviceModelUID = "selectedAudioDeviceModelUID"
        static let prioritizedDevices = "prioritizedDevices"
        static let affiliatePromotionDismissed = "VoiceInkAffiliatePromotionDismissed"
        static let selectedLanguages = "SelectedLanguages"

        static let aiProviderApiKey = "aiProviderApiKey"
        static let licenseKey = "licenseKey"

        // Obfuscated keys for license-related data
        enum License {
            static let trialStartDate = "VoiceInkTrialStartDate"
        }
    }

    // MARK: - AI Provider API Key
    var aiProviderApiKey: String? {
        get { string(forKey: Keys.aiProviderApiKey) }
        set { setValue(newValue, forKey: Keys.aiProviderApiKey) }
    }

    // MARK: - License Key
    var licenseKey: String? {
        get { string(forKey: Keys.licenseKey) }
        set { setValue(newValue, forKey: Keys.licenseKey) }
    }
    
    // MARK: - Trial Start Date (Obfuscated)
    var trialStartDate: Date? {
        get {
            let salt = Obfuscator.getDeviceIdentifier()
            let obfuscatedKey = Obfuscator.encode(Keys.License.trialStartDate, salt: salt)
            
            guard let obfuscatedValue = string(forKey: obfuscatedKey),
                  let decodedValue = Obfuscator.decode(obfuscatedValue, salt: salt),
                  let timestamp = Double(decodedValue) else {
                return nil
            }
            
            return Date(timeIntervalSince1970: timestamp)
        }
        set {
            let salt = Obfuscator.getDeviceIdentifier()
            let obfuscatedKey = Obfuscator.encode(Keys.License.trialStartDate, salt: salt)
            
            if let date = newValue {
                let timestamp = String(date.timeIntervalSince1970)
                let obfuscatedValue = Obfuscator.encode(timestamp, salt: salt)
                setValue(obfuscatedValue, forKey: obfuscatedKey)
            } else {
                removeObject(forKey: obfuscatedKey)
            }
        }
    }

    var audioInputModeRawValue: String? {
        get { string(forKey: Keys.audioInputMode) }
        set { setValue(newValue, forKey: Keys.audioInputMode) }
    }

    var selectedAudioDeviceUID: String? {
        get { string(forKey: Keys.selectedAudioDeviceUID) }
        set { setValue(newValue, forKey: Keys.selectedAudioDeviceUID) }
    }

    var selectedAudioDeviceModelUID: String? {
        get { string(forKey: Keys.selectedAudioDeviceModelUID) }
        set { setValue(newValue, forKey: Keys.selectedAudioDeviceModelUID) }
    }

    var prioritizedDevicesData: Data? {
        get { data(forKey: Keys.prioritizedDevices) }
        set { setValue(newValue, forKey: Keys.prioritizedDevices) }
    }

    var affiliatePromotionDismissed: Bool {
        get { bool(forKey: Keys.affiliatePromotionDismissed) }
        set { setValue(newValue, forKey: Keys.affiliatePromotionDismissed) }
    }

    // MARK: - Selected Languages (Multiple)
    var selectedLanguages: [String] {
        get {
            if let data = data(forKey: Keys.selectedLanguages),
               let languages = try? JSONDecoder().decode([String].self, from: data) {
                return languages.isEmpty ? ["en"] : languages
            }
            // Migration: check for old single language setting
            if let oldLanguage = string(forKey: "SelectedLanguage") {
                return [oldLanguage]
            }
            return ["en"] // Default to English
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                setValue(data, forKey: Keys.selectedLanguages)
            }
        }
    }
} 
