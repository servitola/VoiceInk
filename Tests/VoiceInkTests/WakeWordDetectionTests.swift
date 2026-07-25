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
