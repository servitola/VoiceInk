# VoiceInk Free Fork - Build Instructions

This document contains the exact steps needed to build and run this fork after rebasing from the original repository.

## Apple Silicon vs Intel — automatic

The build auto-detects the host CPU, so the **same command works on both**:

```bash
make build          # install: see the identity below
```

Never plain `make local`: it signs ad-hoc, so macOS revokes the app's permissions on
every reinstall (it now refuses to overwrite a stably-signed `/Applications/VoiceInk.app`
unless you pass `FORCE_ADHOC=1`).

The installed app is signed with the **Developer ID** (team `NZNV266K59`) since 2026-10-02,
and macOS pins the TCC grants to that. Install by hand with the same identity, by hash —
the Makefile splices it into `codesign` unquoted:

```bash
make local LOCAL_SIGN_IDENTITY="$(security find-identity -v -p codesigning \
  | awk 'index($0, "Developer ID Application: Vladislav Konovalov") {print $2; exit}')"
```

Any other identity is a different designated requirement, and every grant drops silently.
`make local-stable` is worse than useless now: it mints the self-signed `VoiceInk Local
Signing` certificate, which only the test gate still uses (`scripts/create-local-signing-cert.sh`
deletes and re-mints it whenever `security find-identity` misses it).

`make check-tcc` answers "does macOS still recognise the installed build?" — see
COMMON-ISSUES.md §12b.

- **Apple Silicon (arm64):** builds the full app, including the Parakeet
  (FluidAudio) engine.
- **Intel (x86_64):** FluidAudio/Parakeet depends on the Apple Neural Engine and
  the `Float16` type, neither of which exists on Intel — the package cannot
  compile there. The build wrapper (`scripts/arch-xcodebuild.sh`) temporarily
  strips the FluidAudio package from the Xcode project, builds with the
  whisper.cpp engine only, then restores the project files. All FluidAudio usage
  in the Swift sources is guarded behind `#if canImport(FluidAudio)`, so the app
  falls back to Intel stubs automatically. On Intel, use a **Whisper** model
  (Parakeet models are hidden).

The committed Xcode project always contains FluidAudio; the strip is transient
and only happens while building on an Intel host. Force a specific path with
`VOICEINK_TARGET_ARCH=x86_64|arm64` (e.g. to test the Intel build from an Apple
Silicon Mac).

## Prerequisites

- macOS 14.0 or later
- Xcode (with Command Line Tools)
- CMake (via Homebrew: `brew install cmake`)

## Quick Build & Install

> These are the raw steps, kept for reference and for a first build from nothing.
> Step 9 signs ad-hoc and step 10 drops the result into `/Applications`, which
> strips every macOS permission the installed app had — the hotkey stops working
> and nothing says why. For a machine that already runs the fork, use
> `make local-stable` instead, and read COMMON-ISSUES.md §12b before hand-signing
> anything.

```bash
cd ~/projects/voiceink

# 1. Build whisper.cpp framework for macOS
cd ../voiceink_dependencies/whisper.cpp
rm -rf build-macos
cmake -B build-macos \
  -DCMAKE_OSX_SYSROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_METAL=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF
cmake --build build-macos --config Release --target whisper -j

# 2. Create xcframework structure
cd ../voiceink_dependencies/whisper.cpp
mkdir -p build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/{Headers,Modules,Resources}

# 3. Copy framework components
cp build-macos/src/libwhisper.dylib build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/whisper
cp ggml/include/*.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/
cp include/*.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/

# 4. Create umbrella header
cat > build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/whisper_umbrella.h << 'EOF'
#import <whisper/whisper.h>
#import <whisper/ggml.h>
EOF

# 5. Create module map
cat > build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Modules/module.modulemap << 'EOF'
framework module whisper {
    umbrella header "whisper_umbrella.h"
    export *
}
EOF

# 6. Create framework Info.plist
cat > build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Resources/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.ggerganov.whisper</string>
    <key>CFBundleName</key>
    <string>whisper</string>
</dict>
</plist>
EOF

# 7. Create framework symlinks
cd build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework
ln -sf Versions/A/Headers Headers
ln -sf Versions/A/Modules Modules
ln -sf Versions/A/Resources Resources
ln -sf Versions/A/whisper whisper
cd Versions
ln -sf A Current

# 8. Create XCFramework Info.plist
cd ../voiceink_dependencies/whisper.cpp/build-apple/whisper.xcframework
cat > Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>LibraryIdentifier</key>
            <string>macos-arm64_x86_64</string>
            <key>LibraryPath</key>
            <string>whisper.framework</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>x86_64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>macos</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
EOF

# 9. Build VoiceInk
cd ~/projects/voiceink
xcodebuild clean -project VoiceInk.xcodeproj -scheme VoiceInk
xcodebuild -project VoiceInk.xcodeproj \
  -scheme VoiceInk \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

# 10. Install to Applications
rm -rf /Applications/VoiceInk.app
cp -R ~/Library/Developer/Xcode/DerivedData/VoiceInk-*/Build/Products/Debug/VoiceInk.app /Applications/

# 11. Copy required dylibs
mkdir -p /Applications/VoiceInk.app/Contents/Frameworks
cp -L ../voiceink_dependencies/whisper.cpp/build-macos/src/libwhisper.*.dylib /Applications/VoiceInk.app/Contents/Frameworks/
cp -L ../voiceink_dependencies/whisper.cpp/build-macos/ggml/src/libggml*.dylib /Applications/VoiceInk.app/Contents/Frameworks/

# 12. Launch
open -a VoiceInk
```

## Language selection (fork feature)

Language is stored **per Mode**: `ModeConfig.selectedLanguages: [String]` is the source of
truth, and the singular `selectedLanguage` is a computed facade over its first element so the
many single-language call sites keep working. Codable decodes both keys and encodes both, so a
downgrade still finds a language. The multi-select `Menu` lives in
`ModeConfigFormView.multiLanguagePicker`; it is offered only for `.whisper` and `.fluidAudio`,
because cloud / Apple-native / streaming providers take one locale per request.

Each backend reduces the set at the edge via `TranscriptionLanguageSupport`:
`validLanguagesOrFallback` clamps a selection to the model, `singleLanguage` degrades it to
`"auto"` for single-locale backends. Whisper consumes the whole set (auto-detect plus
`WhisperPrompt.combinedPrompt(for:)` biasing) through `WhisperContext.setLanguages`.

**Parakeet's language parameter is a script filter, not language conditioning.** FluidAudio's
`Language` maps to a `Script` (latin / cyrillic / greek) and the v3 TDT decoder drops top-K
tokens of other scripts; `AsrManager.transcribe` takes a single `Language?` where `nil` means
no filtering. So `FluidAudioModelManager.languageHint(from:for:)` returns a representative
language when the selection sits in one script and `nil` when it spans several. Consequence:
Parakeet V3 has exactly four reachable behaviours — no filter, latin, cyrillic, greek — and
picking `ru + en + el` is identical to auto-detect. Multi-select there expresses intent and
drives the UI; it cannot improve accuracy on a mixed-script selection. Real per-language
restriction would need a fork of FluidAudio (pinned to upstream `FluidInference/FluidAudio@main`).

Tests: `VoiceInkTests/TranscriptionLanguageSelectionTests.swift`.

## Required Code Changes After Rebase

If you rebase from the original repository, ensure these changes are made:

### 1. UserDefaults Keys (VoiceInk/Services/UserDefaultsManager.swift)

Add these keys to the `Keys` enum (around line 11):

```swift
static let aiProviderApiKey = "aiProviderApiKey"
static let licenseKey = "licenseKey"
```

### 2. Disable CloudKit (VoiceInk/VoiceInk.swift)

In the `createPersistentContainer` method, change line ~152 from:

```swift
cloudKitDatabase: .private("iCloud.com.prakashjoshipax.VoiceInk")
```

to:

```swift
cloudKitDatabase: .none
```

### 3. LicenseViewModel Stub (VoiceInk/Models/LicenseViewModel.swift)

If the file was removed during rebase, create a minimal stub:

```swift
import Foundation
import AppKit

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
    @Published private(set) var activationsLimit: Int = 999

    static let shared = LicenseViewModel()

    init() {
        licenseState = .licensed
    }

    var hasVerifiedLicense: Bool { true }
    var diagnosticLicenseStatus: String { "Licensed (free fork)" }
    var usageRestrictionMessage: String? { nil }

    @discardableResult
    func startTrial() -> Bool { true }
    func validateLicense(_ licenseKey: String = "") async { licenseState = .licensed }
    func deactivateLicense() async {}
    func revalidateLicense() {}
    func checkLicenseStatus() { licenseState = .licensed }
    func refreshLicenseState() { licenseState = .licensed }
    func removeLicense() {}
}
```

This stub is the fork's entire licensing story, so it compiles only while it
covers every member upstream calls — and upstream keeps adding to that list.
After a rebase, check what the app actually wants before trusting the block
above:

```bash
grep -rn "LicenseViewModel\." VoiceInk | grep -v Models/LicenseViewModel.swift
```

The 2.1 rebase dropped `shared`, `hasVerifiedLicense` and
`diagnosticLicenseStatus` and changed two signatures. `HEAD` then stopped
compiling — which is how Sparkle got away with replacing the fork for so long:
nobody could rebuild it to notice.

### 4. Kill Sparkle (VoiceInk/Info.plist, VoiceInk/VoiceInk.swift)

A rebase brings back upstream's `SUFeedURL`, `SUPublicEDKey` and
`SUEnableAutomaticChecks`/`SUScheduledCheckInterval`, and restores an `UpdaterViewModel`
that constructs `SPUStandardUpdaterController(startingUpdater: true, ...)`. Left in place,
the app checks upstream's appcast every four hours and installs the vendor's signed DMG
over this fork — see the 2026-07-29 incident in the handoff below.

Strip those keys from `Info.plist` (keeping `SUEnableAutomaticChecks` as `<false/>` is the
belt-and-braces) and reduce `UpdaterViewModel` to inert stubs: `canCheckForUpdates` and
`automaticallyChecksForUpdates` stay `false`, `checkForUpdates()` and
`setAutomaticallyChecksForUpdates(_:)` do nothing. `SettingsView` and `MenuBarView` need
only that surface. Do not delete the type — both take it from the environment.

`VoiceInkTests/UpdaterViewModelTests.swift` fails if any of this regresses.

### 5. About tab and GitHub star prompt

The sidebar's About tab renders the fork's own `Features/About/AboutView.swift` — version
and links, no purchase, trial, key or affiliate UI. `ContentView` must route `.license` to
`AboutView()`; a rebase that brings back `LicenseManagementView()` there brings the
paywall screen back with it. The vendor's licensing views stay in the tree as dead code on
purpose: deleting files upstream keeps editing turns every rebase into a modify/delete
conflict.

`GitHubStarPromptCoordinator.shouldShow` returns `false` under `LOCAL_BUILD`, which keeps
both the Dashboard card and its footer button hidden.

## Troubleshooting

### Build fails with "Library not loaded: @rpath/libwhisper.1.dylib"

Make sure step 11 (copying dylibs) was completed.

### App crashes on launch with CloudKit errors

Verify step 2 in "Required Code Changes" - CloudKit must be disabled.

### "Unable to import whisper module"

The whisper.xcframework wasn't built correctly or with wrong SDK. Ensure you:
- Use the exact CMake command from step 1
- Specify `-DCMAKE_OSX_SYSROOT` to force macOS SDK (not iOS Simulator)

### Framework built for wrong platform

Check the platform with:
```bash
otool -l ../voiceink_dependencies/whisper.cpp/build-macos/src/libwhisper.dylib | grep -A 3 "platform"
```

Should show `platform 1` (macOS), not `platform 7` (iOS Simulator).

## Dependency Path Convention

All build tooling references dependencies via **relative paths**, never absolute
ones — no machine- or drive-specific paths are committed. Layout: this repo and
`voiceink_dependencies/` are siblings, so deps live at `../voiceink_dependencies`
relative to the repo root. `DEPS_DIR` is derived from each file's own location
(Makefile: `$(CURDIR)/../voiceink_dependencies`; scripts: from `${BASH_SOURCE}`)
and can be overridden with `make DEPS_DIR=/custom/path` or `export DEPS_DIR=…`.
The Xcode file ref and `Modules/whisper_umbrella.h` include are also relative.

## Notes

- This build is **unsigned** and uses local storage only (no iCloud sync)
- The Makefile in the repo won't work correctly - use these instructions instead
- Whisper.cpp dependencies are built as dynamic libraries and must be copied to the app bundle
- The xcframework structure is manually created because the original build script targets iOS

## Whisper framework must be self-contained (important)

The reliable local build path is `./build-macos-framework.sh` (static `.a`
libs) followed by `./make-framework.sh`, which links a **self-contained**
`whisper` dylib (ggml force-loaded in, `@rpath/whisper.framework/whisper`
install name, zero external `libggml*.dylib`). Do NOT ship the *dynamic*
whisper build (whisper.cpp `build-xcframework.sh`): its `whisper` binary has
`LC_LOAD_DYLIB @rpath/libggml*.0.dylib` plus baked-in absolute `LC_RPATH`s,
and since the app only embeds `whisper.framework`, the ggml dylibs are missing
at runtime -> app crashes at launch with `Library not loaded:
@rpath/libggml.0.dylib`. Verify a good framework: `otool -L .../whisper` shows
no `ggml` lines. `make whisper` skips rebuilding when `build-apple/` already
exists, so a stale/dynamic xcframework there silently poisons every rebuild -
delete `build-apple/` to force a clean self-contained rebuild.

## Automated upstream sync

A job outside this repo keeps the fork rebased, built, released and installed:
`~/projects/forks/jobs/voiceink/sync.sh`, LaunchAgent `com.servitola.voiceink-upstream-sync`,
Mon/Thu/Sat 04:30, log `~/projects/forks/logs/voiceink-upstream-sync.log`. Its header
comments are the documentation; the short version:

- Rebase onto `github.com/main`; a conflict goes to an agent that may only edit files.
- Gate: build-for-testing and `VoiceInkTests`, DerivedData in
  `~/.cache/voiceink-upstream-sync/test-dd` — on the internal disk, because a test host
  loaded from `/Volumes/SanDisk` waits on a Removable Volumes TCC prompt (see
  COMMON-ISSUES.md §22). A red gate gets two agent rounds, then stops.
- Install: `make local` signed with the **Developer ID**, then publish: push `main`,
  `publish-app.sh --notarize` re-signs a copy hardened, notarizes, staples, releases it
  and bumps `servitola/tap/voiceink`, and brew reinstalls from the tap.

`.git/hooks/pre-push` is a symlink to `jobs/voiceink/pre-push` in that repo: `main` can be
pushed only as the commit the job last verified. Re-create the link after a fresh clone.

## Wake word (fork feature)

`WakeWordListeningService` captures through `CoreAudioRecorder` and posts
`.toggleRecorderPanel` when it hears the wake word — to start dictation, and again to finish
it. Recognition is either a local Parakeet model gated by Silero VAD (the default, offline)
or `SFSpeechRecognizer`. The notes below are what makes the design non-obvious.

**It heard nothing at all, and that was the whole bug.** For every session before `9759d2e`
the detector was fed pure digital silence. It used an `AVAudioEngine` input tap with the
device bound via `inputNode.auAudioUnit.setDeviceID(...)`; against the user's USB microphone
the engine started without error and **the tap closure was then never called once** — measured
as `0 frames tapped, peak input level 0.0000` over a full 52 s session, while a dictation
recorded minutes earlier on the same build and the same device peaks at 19976/32767. So it
was never the room being quiet, never TCC, never the microphone. Capture now goes through
`CoreAudioRecorder`, the AUHAL path that records every dictation, and the same session logs
880770 frames at peak 0.3857. **Do not put AVAudioEngine back here.**

**Keep it observable.** `lastRecognizedText` existed but was never logged and never displayed,
so "не срабатывает" was unfalsifiable across several sessions and the bug above survived all
of them. The detector now logs what it heard at debug level, reports frames-tapped and peak
input level per session (and on a timer, since the local engine has no session that ends),
and shows the last recognised text in settings. Diagnose from those before touching anything.

**Microphone identity.** A USB device's `kAudioDevicePropertyDeviceUID` embeds the port's
location ID (`AppleUSBAudioEngine:...:USB PnP Audio Device:2120000:2`), so it changes when
the device moves to another port or hub. Matching on the UID alone silently loses the device.
Everything therefore resolves through `AudioDeviceManager.findAvailableDevice(uid:modelUID:)`,
which falls back to the stable `kAudioDevicePropertyModelUID`. The wake word settings persist
`wakeWordMicrophoneUID` + `wakeWordMicrophoneModelUID` + `wakeWordMicrophoneName`, and
`resolveInputDevice()` re-pins the saved UID when the device reappears under a new one.
`getCurrentDevice()`'s `.prioritized` branch had the same UID-only bug and now uses the same
helper — that bug is why a user can end up with the same physical mic listed three times in
`prioritizedDevices`.

**Strict device policy.** When a microphone is chosen explicitly and it is not connected, the
detector stays idle and sets `microphoneUnavailable` instead of falling back. Falling back
would grab the built-in or headset mic, which is exactly what the feature must not do — an
always-open input on a Bluetooth headset also forces it into HFP and wrecks playback.
Only "Same as Recording" (empty UID) follows `AudioDeviceManager`.

**Staying alive.** A single speech recognition request is capped around a minute, so
`scheduleRestart` cycles the session every ~50 s (jittered) instead of waiting for the error
path, and recognition errors back off 1→2→4→…→30 s. `requiresOnDeviceRecognition` follows
`speechRecognizer.supportsOnDeviceRecognition` — server-side recognition would rate-limit an
always-on listener and stream the room to Apple continuously. All of this is Apple-only: a
local model has no session that expires, so cycling it would just reload the model, and it
has no server to fall back to. Speech Recognition authorization is likewise demanded only
for the Apple backend, or offline detection would be blocked on a grant it never uses.

**Apple Speech is unusable on this machine, and silently so.** With macOS Dictation off the
request fails with `kLSRErrorDomain 201` and falls back to Apple's servers, and the server
recogniser then returns **nothing at all, with no error** — 103 s of good audio (831810
frames, peak 0.099) produced zero results. Turning on System Settings → Keyboard → Dictation
makes it run on device. The local engine does not need any of that.

**Say it again to finish.** `wakeWordStopsRecording` (default on) makes the wake word a
toggle: the second one ends dictation through the same `.toggleRecorderPanel` notification.
Three things fall out of it. The detector must keep the microphone through the recording, so
`toggleRecord` and `canStartListening` both make an exception for `.recording` — and must
give it back the instant recording ends, via the `recordingState` didSet, because its model
would otherwise queue behind the one transcribing the dictation on the same shared
`FluidAudioTranscriptionService` actor. A cooldown (2.5 s) is mandatory: recognisers report a
growing utterance incrementally and the wake word is in every partial, so one spoken word
used to fire repeatedly — harmless when a trigger only started recording, not harmless when
the next one stops it. And `removeWakeWord` strips the closing word off the tail as well as
the head; note its head path was rewritten to work on the trimmed text, since it used to
re-derive everything from the original and would have discarded the tail removal.

**Finish and send: the second word.** `wakeWordSend` (empty by default) is an optional second
word that only ever *ends* dictation, and additionally presses `wakeWordSendKey` (default
Return) once the text is pasted — dictate a message and send it without touching the keyboard.
Four things about it are not obvious.

*Which words are live depends on the state, and that decision is a pure function.*
`WakeWordListeningService.selectTrigger(primary:send:in:isRecording:stopsRecording:)` is the
only place the rules live: idle → only the primary word, and it starts a recording; recording
→ the send word first (it wins a tie, being the more specific command), then the primary word
**only if `wakeWordStopsRecording` is on**. That last clause is the subtle one. A configured
send word forces the detector to hold the microphone for the whole recording, which is the
first time the primary word is audible mid-dictation at all — without the clause it would
silently gain a power the user switched off. The engine feeds state in through
`isRecordingActive`, the sibling of `canStartListening`.

*Mic ownership is now "can anything finish by voice", not "does the wake word finish".*
`VoiceInkEngine.voiceCanFinishDictation` is that predicate and replaces the bare
`wakeWordStopsRecording` read in `toggleRecord`, `canStartListening` and
`handleWakeWordDetection`.

*The Auto Send override is one-shot, and its lifetime is the point.* Upstream 2026-09-21
(`ac4b13e8`) deleted the per-Mode `AutoSendKey` and made Finish and Send a *global*
`FinishAndSendKey` (`FinishAndSendSettings`), pressed only when the caller asks — the
recorder panel's send action passes `sendAfterPaste: true` down `toggleRecord` → pipeline →
delivery. The wake word carries its own key (`wakeWordSendKey`) and its own decision to send,
so it still goes through `OutputRuntimeConfiguration.autoSendKey`, which the fork keeps as a
defaulted `.none` field meaning "no override": `pendingAutoSendOverride` on the engine and
`OutputRuntimeConfiguration.overridingAutoSendKey` set it for that single dictation, and
`TranscriptionDelivery` prefers it over the global key when it is enabled.
It is set only when a recording is actually running, spent inside the `outputConfiguration`
closure `runPipeline` hands the pipeline, and cleared again whenever a new recording starts.
That last clear is not belt-and-braces: the pipeline asks for the output configuration *after*
transcribing, so a failed transcription — or a cancellation, which never enters `runPipeline`
at all — never spends the override, and it would sit armed to press Return into the next,
unrelated dictation. Consuming on first read is safe because the pipeline's second call
(`outputForDelivery ?? outputConfiguration()`) only happens for an assistant follow-up or a
failed transcription, and delivery returns before reading `output` in both.

*It is inert outside Paste modes, by construction.* The key is pressed inside
`TranscriptionDelivery.paste`, which `deliver` only reaches after branching `.respond` and
`.customCommand` away, so under those Modes the send word just finishes the dictation. The settings copy says so rather than the code guarding it twice.

`removeWakeWord` strips the send phrase off the tail unconditionally — it always ends
dictation, whatever the primary word's own switch says — before the existing primary-word
tail and head passes.

**The recogniser decides how many words it heard, and that broke tail removal.** The first
version of `removeTrailingWakeWord` read exactly as many trailing words as the configured
phrase had. That is wrong for a made-up word: `авадакедавра` came back from Parakeet as
**"Авада Кедавра"**, so a one-word-wide tail was `кедавра` — five edits from the whole word,
past the Levenshtein-2 threshold — and the closing word rode into the transcript and out to
Telegram. Proven, not guessed: `transcription.text` is assigned at
`TranscriptionPipeline.swift:149`, *after* removal at line 115, so the stored text is the
post-removal text, and the store held the word.

The fix is to stop trusting the width. Several tail widths are tried (`phraseWordCount + 2`
down to 1) and each candidate is compared with **spaces and punctuation removed**, which makes
"Авада Кедавра", "авада, кедавра." and "авадакедавра" the same string — and incidentally
also catches the mirror case, a configured phrase the recogniser ran together. Exact matches
are tried at every width before any fuzzy one, so widening the search cannot let a near miss
eat real words while a clean match exists at another width.

Known limitation, deliberately left: the **head** path still matches only the first word, so a
split *start* word would leave half of it behind. No evidence of it happening — the start word
is usually spoken before the recording opens and never reaches the transcript at all — and
widening a head match is riskier than widening a tail one, since it eats the beginning of real
content.

**`open -a VoiceInk` may launch a completely different build.** Every `xcodebuild` run
registers its output bundle with LaunchServices, so a plain `make local-stable` install can
leave three or four registered `VoiceInk.app`s — `.local-build/`, `build/test-dd/` from a test
run, and a stale `~/Library/Developer/Xcode/DerivedData/` copy. `open -a VoiceInk` then picks
one by name, and it is not necessarily the one in `/Applications`. A DerivedData copy is the
worst case: it was built without `LOCAL_BUILD` and *with* the iCloud entitlements, so it dies
in `PFCloudKitContainerProvider containerWithIdentifier:` on the CoreData CloudKit queue —
which reads exactly like "my change crashed the app". Check `procPath` in the `.ips` report
before believing that. To clean up: `lsregister -u <each stray bundle>`, then
`lsregister -f -R -trusted /Applications/VoiceInk.app`. `open /Applications/VoiceInk.app` is
not a reliable workaround; LaunchServices can still redirect it.

**The command word: a third word, and it is deliberately not a wake word.** Say the start
word, then a word of your choosing, and the rest of the dictation is a command: it goes to
the Mode that word belongs to instead of the focused app — a `.customCommand` Mode shells
out, so the text never reaches whatever has focus. `wakeWordCommandModeId` (unset by
default) names that Mode; the Wake Word settings screen edits the word itself, in a field
beside the other two.

*The detector must never answer to it.* An earlier version made it a real third wake word
that started a dictation hands-free, and that was wrong: starting recordings is the start
word's job, and a detector that answers to the command word opens a recording every time the
word is said aloud. `WakeWordTrigger` therefore has no `command` case at all — the word
never reaches `selectTrigger`. `aModesTriggerWordDoesNotStartADictation` and its sibling are
there to keep it that way.

*The word is stored as the Mode's trigger word, not as a setting of its own.* The transcript
side already works this way: `ModeTriggerWordDetectionService`, called from
`TranscriptionPipeline.run` *before* the output configuration is resolved, is what matches
the word mid-dictation, selects the Mode and strips the word out of the text. One copy is
what stops the word the settings screen shows from drifting away from the word the pipeline
matches — two copies would eventually leave the command wedged in the middle of its own
text. `configureCommandWord` writes through to `ModeConfig.triggerWords`; the settings field
is comma-separated so a Mode that already had several trigger words keeps all of them.

*Nothing about it leaks into the next dictation.* `beginApplyingConfiguration` re-resolves
the active Mode on *every* recording start, so a trigger-word Mode switch lasts exactly one
dictation. `removeWakeWord` deliberately does not touch this word: it runs *before*
trigger-word selection, so stripping it there would hide it from the detector that needs it.

**Restart safety.** Every start/stop bumps a `generation` token that all async continuations
check before touching shared state, and `stopListening()` tears down unconditionally. The old
`guard isListening` could skip teardown after a lost race and leave the engine holding the mic.

**Resume after dictation.** `resumeWakeWordListeningIfEnabled()` is driven by a `didSet` on
`VoiceInkEngine.recordingState`, not only by the panel-dismiss hook — that hook fires from
inside the pipeline while the state is still `.transcribing`, so its `== .idle` guard always
failed and listening never came back after the first dictation.

**Startup order.** `initializeWakeWordService()` waits for `AudioDeviceManager` to publish its
device list before auto-starting; that list arrives via `DispatchQueue.main.async`, and
starting first bound the engine to the system default mic.

**The local engine, and the crash that got the first attempt reverted.** Silero VAD (~1 MB,
Neural Engine) gates a Parakeet TDT model, so the model runs on speech instead of on every
second of silence: measured at ~2 % CPU and 225 MB RSS while listening. Both come from
FluidAudio and are shared with dictation through the app's one
`FluidAudioTranscriptionService`, so the model is loaded once, not twice.

The first attempt (`6a27634` / `fc8566f`) killed the app whenever the main window was
presented while the detector captured: `EXC_BAD_ACCESS` in `swift_task_isCurrentExecutor`
checking the executor for a SwiftData dynamic property (`DashboardContent`'s `@Query`), no
VoiceInk frame in the trace. It was reverted in `c61cdc7`. What the bisect established, by
script rather than by reading code:

| Build | Wake word | Open main window ×6 |
|---|---|---|
| `903af13` (before the work) | on | 6/6 clean |
| `143532e` (mic + failure fixes) | on | 6/6 clean |
| `fc8566f` (local engine) | on, local model | crash on 1st |
| `fc8566f` | on, Apple Speech | crash on 1st |
| `fc8566f` | on, microphone missing so no capture | 6/6 clean |
| `fc8566f`, `syncWakeWordState` disabled | on | crash on 2nd |
| `5d4d9f1` (restored, this design) | on, local model | 6/6 clean |

So it needed live audio capture, was independent of the backend, and was not the `@Published`
mirroring — a heap-corruption signature pointing at the `any WakeWordRecognizer` existential
being called from the realtime render thread, with backends running `async` off the main actor
where the pre-refactor code did everything inline in a `@MainActor` method.

The restored engine removes both halves of that rather than diagnosing them. There is no
protocol and no existential — `startRecognition` branches on the engine kind into two concrete
paths — and nothing runs on the realtime thread at all, because `CoreAudioRecorder` hands over
16 kHz mono chunks from its own processing queue. `LocalWakeWordRecognizer` therefore only ever
receives plain `[Float]`. It stays an actor: `start`/`stop` arrive from the main actor while
the processing task mutates the same sample buffers.

Guard Malloc was never needed. Reproduce with `scripts/wake-word-crash-repro.sh` (kept this
time). Independent confirmation: every VoiceInk crash report on 2026-07-25 is from 21:59–22:31,
i.e. the reverted builds, and none after.

**Startup serialisation.** Three callers race at launch — auto-start, device-list arrival and
the idle-state hook. Each got past the `isListening` check while the others awaited, and the
log showed two `Local wake word recognizer started` lines for one start: two models loaded and
two capture sessions opened, with the generation token cleaning up only afterwards. Starts are
chained through `startTask`.

Tests: `VoiceInkTests/WakeWordDetectionTests.swift`.

## Running the unit tests

Testing takes the same flags the local *app* build takes, not just
`-only-testing`. Unlike a plain `build`, `test` has to **launch** the host app, and it dies
before the harness connects under anything less:

```bash
./scripts/arch-xcodebuild.sh -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -destination 'platform=macOS' -only-testing:VoiceInkTests \
  -derivedDataPath .local-build-test -xcconfig LocalBuild.xcconfig \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGN_ENTITLEMENTS="$PWD/VoiceInk/VoiceInk.local.entitlements" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD' \
  test
```

Each flag earns its place, and the failure modes look nothing like each other:
`CODE_SIGNING_ALLOWED=NO` → the app is killed at launch; the project's own
`DEVELOPMENT_TEAM` → "entitlements require a development certificate"; a *local* signing
cert with `DEVELOPMENT_TEAM=""` → dyld refuses `whisper.framework` and `VoiceInk.debug.dylib`
for "different Team IDs"; and without `LOCAL_BUILD` the app aborts inside CloudKit setup,
since ad-hoc signing cannot carry the iCloud entitlement. `-only-testing:VoiceInkTests` is
still needed on its own account: a plain `test` also builds `VoiceInkUITests`, whose runner
is rejected by Gatekeeper ("VoiceInkUITests-Runner is damaged") under the local unsigned
build, failing the whole run for an unrelated reason. The two `-skip*Validation` flags are
the same ones `XCB_FLAGS` passes in the Makefile — see COMMON-ISSUES.md §19.

Two more traps:

- `print()` inside a test never reaches the xcodebuild log. Write to a file under
  `NSTemporaryDirectory()` and read it afterwards.
- Xcode still *builds* `VoiceInkUITests` even when `-only-testing` excludes it, and writing
  into the previously signed `VoiceInkUITests-Runner.app` fails with `Operation not
  permitted` (App Management protection, `com.apple.provenance`). Delete the stale bundle:
  `rm -rf .local-build-test/Build/Products/Debug/VoiceInkUITests-Runner.app`.

Known-failing on `main`: `WordReplacementServiceTests/underscoreCountsAsWordChar` — the
Unicode word boundary treats `_` as a separator, so `foo_клод_bar` still gets replaced.
`WakeWordRemovalTests/leavesTextAloneWhenNoSendWordIsConfigured` is order-flaky.

## Handoff

**Latest (2026-08-14): the nightly sync had never once succeeded; rewritten without an
agent, `HEAD` un-broken, 2.11 installed.** The 04:15 job had been reporting `FAILED` every
day since it was created — the log contains no `VERIFIED ok` at all. The rebase half
always worked; the gate half never ran, so nobody learned that `HEAD` had not compiled
since the 08-14 rebase (fourth time this has happened).

**`e041d21` — duplicate `getCurrentDevice()`.** Upstream `630ae52` moved it into the new
`AudioDeviceManager+RecordingRouting` extension. Our wake-word commit had edited it in
place, so the rebase replayed that edit as a fresh *addition* in
`AudioDeviceManager.swift`, conflict-free, and both copies survived: `ambiguous use of
getCurrentDevice()` in `Recorder.swift` and `MenuBarView.swift`. Deleting ours lost
nothing — upstream's `.prioritized` branch already resolves through
`findAvailableDevice(uid:modelUID:)`, which is the fix ours carried. **This is the shape
to expect from every rebase: our patch replays cleanly and still does not build.**

**Why the gate never ran.** 08-03…08-09 it sat *after* the install and the install could
not sign. Once reordered, 08-12…08-14 it hung in `SecItemCopyMatching`: SwiftPM asks the
login keychain for `github.com` credentials before downloading a binary artifact (upstream
2.11 added `TranscribeCpp`), and that is an authorization dialog nobody is awake to click.
Fixed with a `machine github.com` line in `~/.netrc` — COMMON-ISSUES.md §20 has the full
mechanism, including why the same build succeeds from a background session.

**`codex exec` is out of the nightly job.** `dotfiles/cron/scripts/voiceink-upstream-sync.sh`
is deterministic shell now: preflight (signing identity present, netrc has github.com)
→ fetch → backup branch → rebase → compile+test gate → `make local` with an explicit
identity → verify. A rebase conflict aborts and asks for a human instead of being
resolved by an agent; `rerere` is on so the manual resolution is reused. Verified live:
`VERIFIED ok — 2.11 (211)`.

**`make local-stable` must never run unattended.** It calls
`scripts/create-local-signing-cert.sh`, which deletes the certificate and mints a new one
whenever `security find-identity` fails to see it — a new Designated Requirement, so every
TCC grant drops silently and the hotkey dies. Use `make local LOCAL_SIGN_IDENTITY=<sha1>`.
The key is backed up at `~/.config/voiceink/local-signing.p12` (password `voiceink-local`);
it existed in exactly one place until now. Also: `security find-identity -v` does **not**
list this certificate — `-v` is "valid only" and a self-signed cert is
`CSSMERR_TP_NOT_TRUSTED`. That is not a missing private key. Check without `-v`.

Unit tests cannot be run from a background session at all — see COMMON-ISSUES.md §21.

---

**2026-07-29: Sparkle had silently replaced this fork with the vendor's build;
fixed, rebuilt, installed, working.** `VoiceInkTests` 85/85, `voiceink transcribe` answers
in 0.4 s, the LiteLLM shim on `:8178` is healthy, and `/Applications/VoiceInk.app` is signed
`VoiceInk Local Signing` with no `SUFeedURL` in its `Info.plist`.

One trigger, two defects, both now committed:

**`5091ab9` — Sparkle installed upstream over the fork.** `Info.plist` still carried
`SUFeedURL = beingpax.github.io/VoiceInk/appcast.xml` and a 14400 s check interval. At 08:57
that day Sparkle downloaded and installed the vendor's signed 2.1 DMG over
`/Applications/VoiceInk.app`. That build reinstates the license gate ("Trial Expired") and
has no CLI transcribe listener, so every `voiceink transcribe` hung in `CFRunLoopRun`
waiting for a reply that could never come. Proof it was Sparkle and not a manual install:
`SULastCheckTime` 08:57:57 UTC against a bundle mtime of 08:57, and the installed bundle was
signed `Developer ID Application: Prakash Joshi (V6J6A3VWY2)`.

The fork publishes no appcast of its own — the checked-in `appcast.xml` is upstream's,
enclosing `Beingpax/VoiceInk/releases/download/v2.1/VoiceInk.dmg` — so there was never
anything legitimate to check against. `UpdaterViewModel` no longer constructs
`SPUStandardUpdaterController` at all. Updating the fork means the nightly sync, or
`git pull && make local LOCAL_SIGN_IDENTITY=<sha1>` by hand (see the 08-14 entry above —
`make local-stable` can mint a fresh certificate and drop every TCC grant).
See "Required Code Changes After Rebase" §4 — a rebase will bring all of this back.

**`d2e7b85` — `HEAD` had not compiled since the 2026-07-28 rebase.** Upstream 2.1 made
`ModeRuntimeConfiguration.mode` non-optional and wrapped `retranscribeAudio`'s return in
`AudioRetranscriptionResult`; `CLIBridgeService` stayed on the old API. This is why the
substitution went unnoticed for a day — the fork could not be rebuilt, so nobody rebuilt it.
The lesson generalises: **an upstream rebase can leave fork-only files uncompilable, and
nothing tells you until you next build.** Worth a pre-push hook or CI that builds and runs
`VoiceInkTests` before anything reaches `origin/main`.

**Later the same day — the hotkey went dead and the signing certificate was why.**
`Ctrl+Shift+Z` stopped recording while the app looked entirely healthy: process alive, shim
on `:8178` answering, `voiceink transcribe` returning in 0.3 s, `Authority=VoiceInk Local
Signing`, no `SUFeedURL`. What gave it away was `tccd`:

```
Failed to match existing code requirement for subject
com.prakashjoshipax.VoiceInk and service kTCCServiceListenEvent
identifier "com.prakashjoshipax.VoiceInk" and certificate leaf = H"909602ca…"
```

macOS had pinned the permissions to a certificate leaf that no longer existed. The keychain
held exactly one `VoiceInk Local Signing` cert, `AC74F829…`, with `notBefore` 12:13:28 UTC —
minted during that afternoon's rebuild. Grants stayed with the dead `909602ca…`, so Input
Monitoring, Microphone, Accessibility and Screen Recording were all silently refused. The
last real microphone recording on disk was 14:07; the first refusal, 14:08:36. Everything
after that in `Recordings/` was a `retranscribed_*` file — old audio replayed through the
History view, which needs no permissions at all.

Fixed by `tccutil reset` of the four services, re-granting, and **restarting the app** — the
grant does not reach a process that is already running, which is why it still looked broken
right after the switches were flipped. Confirmed working from the log: `CoreAudioRecorder`
opened the mic, `StreamingTranscriptionService` connected to Parakeet V3, and the pipeline
returned `Test test.` from a live mic recording.

The corresponding cure: `make local` now refuses to overwrite a stably-signed install
(override with `FORCE_ADHOC=1`), `create-local-signing-cert.sh` checks for a usable
*identity* rather than a bare certificate, clears an orphan itself, and shouts when it mints
a new certificate, and `make check-tcc` reports the mismatch straight from the `tccd` log.
COMMON-ISSUES.md §12b carries the full account.

Backlog and topic entry point now live at `~/projects/serho_topics/voiceink/`
(`BACKLOG.md`, `AGENTS.md`, symlink `repo`).

Next steps, in priority order:

- **`VIK-001` — rip out the license UI.** The fork is free and `licenseState` is hardcoded
  `.licensed`, but ~1400 lines of vendor paywall remain: `LicenseManagementView.swift` (872),
  `LicenseView.swift` (61), `TrialMessageView.swift` (80), `OnboardingLicenseCards.swift`
  (251), `LicenseViewModel.swift` (69), `LicenseManager.swift` (105). The sidebar's "About"
  tab still offers "Buy License", "Lost Key?", "Manage License", "Deactivate", a key field
  and an "Affiliate Program — Earn 30% from referrals" row. **Open question for the owner,
  asked but not yet answered: drop the "About" tab entirely, or keep it and strip only the
  licensing?** It also holds genuinely useful links — Recommended Models, Documentation,
  Videos & Guides, Changelog, Report or Feedback.
- **`VIK-003` — verify the replacement dictionary by eye.** The defaults domain survived the
  substitution intact (shortcuts, `isWakeWordEnabled`, `modeConfigurationsV2`, provider keys).
  The dictionary moved to SwiftData (`HasMigratedDictionaryToSwiftData_v2`), so it cannot be
  checked from a shell — open Dictionary in the app and confirm the RU fixups are there. If
  empty, import `~/projects/dotfiles/voiceink/VoiceInk_Settings_Backup.json` (`version` 1.74,
  behind the app's schema) and re-export a fresh snapshot.
- Still open from 2026-07-26, untouched by this session: dictate a mixed ru/en/el phrase on
  Parakeet V3 and confirm the `Languages` menu renders with the multi-script caption and the
  selection survives an app restart.

## Repository State

After successful build, your fork should have:
- Multiple languages selector enabled
- No trial/buy banners
- All licensing checks returning "licensed"
- Local-only storage (no CloudKit)
