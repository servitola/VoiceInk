import Foundation
import Testing

@testable import VoiceInk

struct WakeWordDetectionTests {

    // MARK: - Wake word matching

    @Test func matchesExactCyrillicWakeWord() {
        #expect(WakeWordListeningService.detectWakeWord("лошадка", in: "лошадка напиши письмо"))
    }

    @Test func matchesRegardlessOfCase() {
        #expect(WakeWordListeningService.detectWakeWord("Лошадка", in: "ЛОШАДКА привет"))
    }

    @Test func matchesMisrecognizedWordWithinTwoEdits() {
        // Speech recognition routinely returns near misses for a made-up word.
        #expect(WakeWordListeningService.detectWakeWord("лошадка", in: "ложадка привет"))
    }

    @Test func doesNotMatchUnrelatedSpeech() {
        #expect(!WakeWordListeningService.detectWakeWord("лошадка", in: "сегодня хорошая погода"))
    }

    @Test func doesNotMatchEmptyTranscript() {
        #expect(!WakeWordListeningService.detectWakeWord("лошадка", in: ""))
    }

    @Test func doesNotMatchWhenWakeWordIsEmpty() {
        // An empty wake word is contained in every string - it must never arm.
        #expect(!WakeWordListeningService.detectWakeWord("", in: "любой текст"))
    }

    // MARK: - Levenshtein

    @Test func distanceOfIdenticalStringsIsZero() {
        #expect(WakeWordListeningService.levenshteinDistance("лошадка", "лошадка") == 0)
    }

    @Test func distanceCountsSingleSubstitution() {
        #expect(WakeWordListeningService.levenshteinDistance("лошадка", "ложадка") == 1)
    }

    @Test func distanceHandlesEmptyOperands() {
        #expect(WakeWordListeningService.levenshteinDistance("", "abc") == 3)
        #expect(WakeWordListeningService.levenshteinDistance("abc", "") == 3)
        #expect(WakeWordListeningService.levenshteinDistance("", "") == 0)
    }
}

/// The closing wake word, spoken to finish dictation, lands in the recording and
/// has to come off the tail.
struct TrailingWakeWordRemovalTests {

    private func strip(_ text: String) -> String {
        TranscriptionOutputFilter.removeTrailingWakeWord(from: text, wakeWord: "лошадка")
    }

    @Test func removesTheClosingWord() {
        #expect(strip("сделай вот это лошадка") == "сделай вот это")
    }

    @Test func keepsTerminalPunctuationTheWakeWordCarried() {
        #expect(strip("сделай вот это лошадка.") == "сделай вот это.")
    }

    @Test func doesNotDuplicateExistingPunctuation() {
        #expect(strip("сделай вот это. лошадка.") == "сделай вот это.")
    }

    @Test func removesAMisrecognizedClosingWord() {
        #expect(strip("сделай вот это лошатка") == "сделай вот это")
    }

    @Test func leavesTextThatDoesNotEndWithTheWakeWord() {
        #expect(strip("сделай вот это") == "сделай вот это")
    }

    @Test func doesNotStripTheWakeWordFromTheMiddle() {
        #expect(strip("лошадка бежит по полю") == "лошадка бежит по полю")
    }

    @Test func aLoneWakeWordLeavesNothing() {
        #expect(strip("лошадка") == "")
    }

    @Test func handlesEmptyInput() {
        #expect(strip("") == "")
    }

    /// `bool(forKey:)` answers false for a key that was never written, and
    /// `@AppStorage`'s default does not write it. That silently disabled wake
    /// word removal for everyone who left the settings toggle alone, while the
    /// UI showed it as on.
    @Test func removalIsOnUntilItIsExplicitlyTurnedOff() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: "removeWakeWordFromTranscription")
        defer { defaults.setValue(original, forKey: "removeWakeWordFromTranscription") }

        defaults.removeObject(forKey: "removeWakeWordFromTranscription")
        #expect(defaults.removeWakeWordFromTranscription)

        defaults.removeWakeWordFromTranscription = false
        #expect(!defaults.removeWakeWordFromTranscription)
    }
}

@MainActor
struct WakeWordDeviceResolutionTests {

    private func makeManager() -> AudioDeviceManager {
        let manager = AudioDeviceManager()
        manager.availableDevices = [
            (id: 91, uid: "AppleUSBAudioEngine:USB PnP Audio Device:2120000:2", name: "USB PnP Audio Device"),
            (id: 93, uid: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone"),
        ]
        return manager
    }

    @Test func findsDeviceByExactUID() {
        let manager = makeManager()
        let found = manager.findAvailableDevice(
            uid: "AppleUSBAudioEngine:USB PnP Audio Device:2120000:2",
            modelUID: nil
        )
        #expect(found?.id == 91)
    }

    @Test func returnsNilWhenNeitherUIDNorModelUIDMatches() {
        // The USB UID embeds the port location ID, so a replug into another port
        // produces a UID that is not in the list. Without a model UID there is
        // nothing left to match on and the caller must not fall back blindly.
        let manager = makeManager()
        let found = manager.findAvailableDevice(
            uid: "AppleUSBAudioEngine:USB PnP Audio Device:1120000:2",
            modelUID: nil
        )
        #expect(found == nil)
    }

    @Test func returnsNilForEmptyIdentifiers() {
        let manager = makeManager()
        #expect(manager.findAvailableDevice(uid: "", modelUID: nil) == nil)
        #expect(manager.findAvailableDevice(uid: "", modelUID: "") == nil)
    }
}

struct WakeWordMicrophonePersistenceTests {

    @Test func roundTripsMicrophoneIdentity() {
        let defaults = UserDefaults(suiteName: "WakeWordMicrophonePersistenceTests")!
        defaults.removePersistentDomain(forName: "WakeWordMicrophonePersistenceTests")

        defaults.wakeWordMicrophoneUID = "AppleUSBAudioEngine:USB PnP Audio Device:2120000:2"
        defaults.wakeWordMicrophoneModelUID = "USB PnP Audio Device:0C76:153F"
        defaults.wakeWordMicrophoneName = "USB PnP Audio Device"

        #expect(defaults.wakeWordMicrophoneUID == "AppleUSBAudioEngine:USB PnP Audio Device:2120000:2")
        #expect(defaults.wakeWordMicrophoneModelUID == "USB PnP Audio Device:0C76:153F")
        #expect(defaults.wakeWordMicrophoneName == "USB PnP Audio Device")

        defaults.removePersistentDomain(forName: "WakeWordMicrophonePersistenceTests")
    }
}
