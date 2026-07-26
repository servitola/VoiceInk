import Foundation

extension UserDefaults {
    enum Keys {
        static let audioInputMode = "audioInputMode"
        static let selectedAudioDeviceUID = "selectedAudioDeviceUID"
        static let selectedAudioDeviceModelUID = "selectedAudioDeviceModelUID"
        static let prioritizedDevices = "prioritizedDevices"
        static let wakeWordMicrophoneUID = "wakeWordMicrophoneUID"
        static let wakeWordMicrophoneModelUID = "wakeWordMicrophoneModelUID"
        static let wakeWordMicrophoneName = "wakeWordMicrophoneName"
        static let wakeWordStopsRecording = "wakeWordStopsRecording"
        static let wakeWordSend = "wakeWordSend"
        static let wakeWordSendKey = "wakeWordSendKey"
        static let wakeWordCommandModeId = "wakeWordCommandModeId"
        static let removeWakeWordFromTranscription = "removeWakeWordFromTranscription"
        static let wakeWordEngine = "wakeWordEngine"
        static let wakeWordModelName = "wakeWordModelName"
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

    /// UID of the microphone the wake word detector listens on.
    /// Empty/nil means "follow the app's recording device selection".
    var wakeWordMicrophoneUID: String? {
        get { string(forKey: Keys.wakeWordMicrophoneUID) }
        set { setValue(newValue, forKey: Keys.wakeWordMicrophoneUID) }
    }

    /// Model UID of the wake word microphone. USB device UIDs embed the port's
    /// location ID and change between ports, so this is the stable identity used
    /// to re-find the same physical device after a replug.
    var wakeWordMicrophoneModelUID: String? {
        get { string(forKey: Keys.wakeWordMicrophoneModelUID) }
        set { setValue(newValue, forKey: Keys.wakeWordMicrophoneModelUID) }
    }

    /// Display name of the wake word microphone, kept so the settings picker can
    /// still name the device while it is unplugged.
    var wakeWordMicrophoneName: String? {
        get { string(forKey: Keys.wakeWordMicrophoneName) }
        set { setValue(newValue, forKey: Keys.wakeWordMicrophoneName) }
    }

    /// Saying the wake word again ends dictation, the way pressing the shortcut
    /// a second time does. Defaults to true, so the feature works without the
    /// key ever having been written.
    var wakeWordStopsRecording: Bool {
        get { object(forKey: Keys.wakeWordStopsRecording) as? Bool ?? true }
        set { setValue(newValue, forKey: Keys.wakeWordStopsRecording) }
    }

    /// A second wake word that finishes dictation *and* presses the send key,
    /// so a message can be dictated and sent without touching the keyboard.
    /// Empty means the feature is off, which is the default.
    var wakeWordSend: String {
        get { string(forKey: Keys.wakeWordSend) ?? "" }
        set { setValue(newValue, forKey: Keys.wakeWordSend) }
    }

    /// Which key the send wake word presses after the paste.
    ///
    /// Read through `object(forKey:)` for the same reason as
    /// `removeWakeWordFromTranscription` below: the key is only written once the
    /// settings picker is touched, and an unwritten key must still mean Return -
    /// pressing nothing is not what "finish and send" says on the tin.
    var wakeWordSendKey: AutoSendKey {
        get {
            guard let raw = object(forKey: Keys.wakeWordSendKey) as? String,
                let key = AutoSendKey(rawValue: raw)
            else { return .enter }
            return key
        }
        set { setValue(newValue.rawValue, forKey: Keys.wakeWordSendKey) }
    }

    /// The mode a command wake word starts a dictation in, if any.
    ///
    /// Only the mode is stored, never the words: the words *are* that mode's
    /// trigger words. Keeping one copy is what guarantees the word that opened
    /// the recording is also the one stripped out of the transcript afterwards.
    /// Nil = no command wake word.
    var wakeWordCommandModeId: UUID? {
        get {
            guard let raw = string(forKey: Keys.wakeWordCommandModeId) else { return nil }
            return UUID(uuidString: raw)
        }
        set { setValue(newValue?.uuidString, forKey: Keys.wakeWordCommandModeId) }
    }

    /// Keep the wake word out of the dictated text.
    ///
    /// Read through `object(forKey:)`, not `bool(forKey:)`: the key is only
    /// written once the settings toggle is actually moved, and `bool(forKey:)`
    /// answers `false` for a key that was never written. That silently disabled
    /// wake word removal entirely for anyone who left the switch alone - which
    /// is everyone, since the UI shows it as on.
    var removeWakeWordFromTranscription: Bool {
        get { object(forKey: Keys.removeWakeWordFromTranscription) as? Bool ?? true }
        set { setValue(newValue, forKey: Keys.removeWakeWordFromTranscription) }
    }

    /// Which recognition backend the wake word detector uses.
    var wakeWordEngine: String? {
        get { string(forKey: Keys.wakeWordEngine) }
        set { setValue(newValue, forKey: Keys.wakeWordEngine) }
    }

    /// Transcription model used when the wake word engine is the local one.
    var wakeWordModelName: String? {
        get { string(forKey: Keys.wakeWordModelName) }
        set { setValue(newValue, forKey: Keys.wakeWordModelName) }
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
