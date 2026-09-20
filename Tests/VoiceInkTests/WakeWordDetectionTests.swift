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

    // MARK: - Choosing between the two words

    private func trigger(
        in text: String,
        send: String = "отправляй",
        isRecording: Bool,
        stopsRecording: Bool = true
    ) -> WakeWordTrigger? {
        WakeWordListeningService.selectTrigger(
            primary: "лошадка",
            send: send,
            in: text,
            isRecording: isRecording,
            stopsRecording: stopsRecording
        )
    }

    @Test func primaryWordStartsDictationWhenIdle() {
        #expect(trigger(in: "лошадка напиши письмо", isRecording: false) == .primary)
    }

    @Test func sendWordDoesNothingWhenIdle() {
        // It finishes dictation. There is nothing to finish.
        #expect(trigger(in: "отправляй уже", isRecording: false) == nil)
    }

    @Test func sendWordFinishesARunningDictation() {
        #expect(trigger(in: "привет как дела отправляй", isRecording: true) == .send)
    }

    @Test func sendWordWinsWhenBothWordsAreHeard() {
        #expect(trigger(in: "лошадка привет отправляй", isRecording: true) == .send)
    }

    /// A configured send word keeps the detector listening through the whole
    /// recording, which is the first time the primary word is audible mid
    /// dictation at all. It must not quietly gain a power the user turned off.
    @Test func primaryWordCannotFinishWhenItsOwnSwitchIsOff() {
        #expect(trigger(in: "лошадка", isRecording: true, stopsRecording: false) == nil)
        #expect(trigger(in: "отправляй", isRecording: true, stopsRecording: false) == .send)
    }

    @Test func primaryWordFinishesWhenItsSwitchIsOn() {
        #expect(trigger(in: "сделал лошадка", send: "", isRecording: true) == .primary)
    }

    @Test func noSendWordConfiguredMeansNoSendTrigger() {
        #expect(trigger(in: "отправляй уже", send: "", isRecording: true) == nil)
    }

    // MARK: - The command word is not a wake word

    /// The word that routes a dictation to a mode must never reach the detector.
    /// Starting recordings is the start word's job, and a detector that answered
    /// to the command word would open one every time it was mentioned aloud.
    @Test func aModesTriggerWordDoesNotStartADictation() {
        #expect(trigger(in: "серго открой телеграм", isRecording: false) == nil)
        #expect(trigger(in: "лошадка серго открой телеграм", isRecording: false) == .primary)
    }

    /// It is an ordinary word of the text mid-dictation, so it must not end one
    /// either — that would cut the sentence mentioning it in half.
    @Test func aModesTriggerWordDoesNotFinishADictation() {
        #expect(trigger(in: "напиши что серго молодец", isRecording: true) == nil)
        #expect(trigger(in: "серго привет отправляй", isRecording: true) == .send)
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
///
/// Serialised: the cases below reach into `UserDefaults.standard`, which every
/// other test in this file shares.
@Suite(.serialized)
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
    /// A private domain, not `.standard`: the test host shares the real app's
    /// preferences, so the old version rewrote the running VoiceInk's own setting
    /// and then raced every sibling test that reads it through
    /// TranscriptionOutputFilter — green alone, red in a full parallel run.
    @Test func removalIsOnUntilItIsExplicitlyTurnedOff() {
        let suite = "VoiceInkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(defaults.removeWakeWordFromTranscription)

        defaults.removeWakeWordFromTranscription = false
        #expect(!defaults.removeWakeWordFromTranscription)
    }

    // MARK: - Multi-word phrases

    @Test func removesAWholeClosingPhrase() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "сделай вот это отправляй сообщение", wakeWord: "отправляй сообщение")
                == "сделай вот это")
    }

    @Test func removesAMisrecognizedClosingPhrase() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "сделай вот это отправляй сообщения", wakeWord: "отправляй сообщение")
                == "сделай вот это")
    }

    @Test func leavesAPhraseThatOnlyPartlyMatches() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "сделай вот это сообщение", wakeWord: "отправляй сообщение")
                == "сделай вот это сообщение")
    }

    @Test func leavesTextShorterThanThePhrase() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "сообщение", wakeWord: "отправляй сообщение") == "сообщение")
    }

    // MARK: - However the recogniser chose to break the word up

    /// The one that shipped broken. A single configured word came back as two
    /// ("авадакедавра" → "Авада Кедавра"), the tail was read one word wide, and
    /// "кедавра" is five edits from the whole word — so the closing word rode
    /// into the text and out to Telegram.
    @Test func removesAClosingWordTheRecogniserSplitInTwo() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "и для людей тоже было бы хорошо Авада Кедавра.",
                wakeWord: "авадакедавра") == "и для людей тоже было бы хорошо.")
    }

    @Test func removesAClosingWordSplitWithPunctuationBetween() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "сделай вот это авада, кедавра", wakeWord: "авадакедавра")
                == "сделай вот это")
    }

    @Test func removesASplitClosingWordThatIsAlsoMisheard() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "сделай вот это авада кедабра", wakeWord: "авадакедавра")
                == "сделай вот это")
    }

    /// The mirror case: a configured phrase that the recogniser ran together.
    @Test func removesAClosingPhraseTheRecogniserMerged() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "сделай вот это отправляйсообщение", wakeWord: "отправляй сообщение")
                == "сделай вот это")
    }

    /// The wider search must not start eating real words. Three trailing words
    /// that merely end in something word-shaped stay put.
    @Test func theWiderSearchDoesNotSwallowRealWords() {
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "и для людей тоже было бы хорошо", wakeWord: "авадакедавра")
                == "и для людей тоже было бы хорошо")
        #expect(
            TranscriptionOutputFilter.removeTrailingWakeWord(
                from: "лошадка бежит по полю", wakeWord: "лошадка") == "лошадка бежит по полю")
    }

    /// An exact match at one width beats a near miss at a wider one, so the
    /// search cannot take an extra word just because it was tried first.
    @Test func anExactMatchWinsOverAWiderNearMiss() {
        #expect(strip("привет мир лошадка") == "привет мир")
    }
}

/// End to end: whichever word ended the dictation was spoken into it, so neither
/// may reach the text that gets pasted.
@Suite(.serialized)
struct WakeWordRemovalTests {

    /// Runs `body` with the wake word settings pinned, then puts them back.
    private func withSettings(
        send: String,
        stopsRecording: Bool,
        _ body: () -> Void
    ) {
        let defaults = UserDefaults.standard
        let originalSend = defaults.object(forKey: "wakeWordSend")
        let originalStops = defaults.object(forKey: "wakeWordStopsRecording")
        let originalRemove = defaults.object(forKey: "removeWakeWordFromTranscription")
        let originalWord = defaults.object(forKey: "wakeWord")
        defer {
            defaults.setValue(originalSend, forKey: "wakeWordSend")
            defaults.setValue(originalStops, forKey: "wakeWordStopsRecording")
            defaults.setValue(originalRemove, forKey: "removeWakeWordFromTranscription")
            defaults.setValue(originalWord, forKey: "wakeWord")
        }

        defaults.setValue("лошадка", forKey: "wakeWord")
        defaults.wakeWordSend = send
        defaults.wakeWordStopsRecording = stopsRecording
        defaults.removeWakeWordFromTranscription = true
        body()
    }

    @Test func stripsTheOpeningWordAndTheClosingSendWord() {
        withSettings(send: "отправляй", stopsRecording: true) {
            #expect(
                TranscriptionOutputFilter.removeWakeWord(from: "лошадка привет мир отправляй")
                    == "Привет мир")
        }
    }

    /// The send word ends dictation on its own, so it comes off the tail whether
    /// or not the plain wake word is allowed to end one.
    @Test func stripsTheSendWordEvenWhenSayingItAgainIsOff() {
        withSettings(send: "отправляй", stopsRecording: false) {
            #expect(
                TranscriptionOutputFilter.removeWakeWord(from: "лошадка привет мир отправляй")
                    == "Привет мир")
        }
    }

    @Test func leavesTextAloneWhenNoSendWordIsConfigured() {
        withSettings(send: "", stopsRecording: false) {
            #expect(
                TranscriptionOutputFilter.removeWakeWord(from: "лошадка привет мир отправляй")
                    == "Привет мир отправляй")
        }
    }

    /// Starting and immediately sending records nothing worth pasting.
    @Test func aStartAndAnImmediateSendLeaveNothing() {
        withSettings(send: "отправляй", stopsRecording: true) {
            #expect(TranscriptionOutputFilter.removeWakeWord(from: "лошадка отправляй") == "")
        }
    }
}

struct AutoSendOverrideTests {

    @Test func overridingReplacesOnlyTheKey() {
        let original = OutputRuntimeConfiguration(
            mode: nil,
            outputMode: .paste,
            autoSendKey: .none,
            customCommand: nil
        )

        let overridden = original.overridingAutoSendKey(.enter)

        #expect(overridden.autoSendKey == .enter)
        #expect(overridden.outputMode == .paste)
        #expect(overridden.mode == nil)
        #expect(overridden.customCommand == nil)
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

