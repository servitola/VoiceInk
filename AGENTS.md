# VoiceInk Free Fork - Build Instructions

This document contains the exact steps needed to build and run this fork after rebasing from the original repository.

## Apple Silicon vs Intel — automatic

The build auto-detects the host CPU, so the **same command works on both**:

```bash
make local-stable   # or: make local / make build
```

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

    init() {
        licenseState = .licensed
    }

    func startTrial() {}
    func validateLicense() async { licenseState = .licensed }
    func deactivateLicense() async {}
    func revalidateLicense() {}
    func checkLicenseStatus() { licenseState = .licensed }
    func removeLicense() {}
}
```

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

## Automated upstream sync (cron)

A nightly job syncs this fork with upstream — it does NOT live in this repo:

- Fragment: `dotfiles_private/cron/cron_jobs/voiceink.private.cron` — 04:15 daily
- Script: `dotfiles_private/cron/scripts/voiceink-upstream-sync.sh`
- Log: `dotfiles/cron/logs/voiceink-upstream-sync.log`

The script does not reimplement the sync: it feeds `.claude/commands/sync-upstream.md`
(the single source of truth) to `codex exec`, so editing that runbook changes what the
cron does. The wrapper owns only the cheap deterministic parts — preflight gates
(repo mounted, on `main`, clean tree, no rebase in progress), the "are we behind?"
check that skips the agent entirely on a no-op day, and an **independent** re-verification
afterwards (upstream is an ancestor, no conflict markers, installed version matches,
bundle carries `Authority=VoiceInk Local Signing`, app actually running) — because an
agent can report success it did not achieve.

**It never pushes.** `ALLOW_PUSH=0` plus a prompt override forbidding `git push`, so
commits accumulate locally and the Telegram notification carries the push command.
Someone must push by hand periodically. Flip `ALLOW_PUSH=1` to change that.

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

*The Auto Send override is one-shot, and its lifetime is the point.* `AutoSendKey` is a
per-Mode setting; finishing by voice overrides it for that single dictation via
`pendingAutoSendOverride` on the engine and `OutputRuntimeConfiguration.overridingAutoSendKey`.
It is set only when a recording is actually running, spent inside the `outputConfiguration`
closure `runPipeline` hands the pipeline, and cleared again whenever a new recording starts.
That last clear is not belt-and-braces: the pipeline asks for the output configuration *after*
transcribing, so a failed transcription — or a cancellation, which never enters `runPipeline`
at all — never spends the override, and it would sit armed to press Return into the next,
unrelated dictation. Consuming on first read is safe because the pipeline's second call
(`outputForDelivery ?? outputConfiguration()`) only happens for an assistant follow-up or a
failed transcription, and delivery returns before reading `output` in both.

*It is inert outside Paste modes, by construction.* `TranscriptionDelivery` gates `autoSendKey`
on `outputMode == .paste`, so under a `.respond` or `.customCommand` Mode the send word just
finishes the dictation. The settings copy says so rather than the code guarding it twice.

`removeTrailingWakeWord` grew to match multi-word phrases (last *N* words joined, then the same
exact-or-Levenshtein test), and `removeWakeWord` now strips the send phrase off the tail
unconditionally — it always ends dictation, whatever the primary word's own switch says —
before the existing primary-word tail and head passes.

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

## Handoff

**Latest (2026-07-26, third wake-word session): the "finish and send" word works, and was
verified live** — the user dictated a message into this very chat with it and it sent itself.
Built with `make local-stable`, installed and running; `VoiceInkTests` 76/76. Design and the
non-obvious parts are in the wake word section above. The log of the run that proves it, with
"лошадка" as the wake word and "авадакедавра" as the send word:

```
🎯 Wake word detected: (primary)      → 🎯 Wake word detected - starting recording
heard: как как поступить авадакидавра?
🎯 Wake word detected: (send)         → 🎯 Send wake word detected - finishing recording and pressing enter
🎯 Closing wake word removed from transcription
📝 After wake word removal: скажешь скажешь мне как поступить
```

Two things that run confirms beyond the unit tests. The send word **is** heard mid-dictation —
9 s after the start here, comfortably past the shared 2.5 s cooldown. And the fuzzy match earns
its keep: Parakeet returned "авадакидавра" for a configured "авадакедавра", one edit away, and
it matched both to trigger *and* to come off the tail.

Still unverified, in rough order of interest: a `.respond`-output Mode (the send word should
just finish, no Return); ⇧⏎ / ⌘⏎ instead of Return; and the "say it again to finish" tumbler
turned **off** while a send word is set — "лошадка" mid-dictation must then not stop anything.

Previous state (2026-07-26, second wake-word session): **the whole round trip works, offline,
and was watched end to end by the user** — which every previous session ended without ever
seeing. Installed and running at `f7a9f9a`.

Say "лошадка" → recording starts. Dictate. Say "лошадка" → it finishes, transcribes and
pastes, with both wake words stripped from the text. Verified live twice in the log:

```
🎯 Wake word detected   (start)
🎯 Wake word detected   (stop)
🎯 Closing wake word removed from transcription
```

Local Parakeet on the user's USB microphone, `engine: localModel, onDevice recognition: true`,
nothing leaving the machine, listening resuming after each dictation.

The reason it never fired was not the recogniser and not the microphone selection fixed in
the previous session: the `AVAudioEngine` tap was **never called at all**, so the detector
was fed digital silence. Capture moved to `CoreAudioRecorder`. Full evidence in the wake word
section — read it before touching the capture path.

Apple Speech remains configurable but is a dead end here until macOS Dictation is enabled;
with it off the server recogniser returns nothing at all, silently. The local engine is the
default and needs none of it. The user's Speech Recognition grant was reset with `tccutil`
during this session (they had accidentally dismissed a prompt), so macOS will ask again if
they ever switch to the Apple backend.

The crash that caused the `c61cdc7` revert does not reproduce with the restored design:
`scripts/wake-word-crash-repro.sh` is 6/6 clean, and no crash report exists after 22:31.

**Two bugs found by using it, both worth remembering.** The starting "лошадка" stopped the
dictation it had just started, because both backends re-report a growing utterance from its
beginning and the word stayed in every later result — fixed by `consumeSegment()`, not by the
cooldown, which only covered the first seconds. And wake word removal from the transcript had
been silently off for everyone forever: `bool(forKey:)` answers false for a key `@AppStorage`
never writes. Check that pattern elsewhere — it fails in exactly the direction that looks
like the feature is on.

Earlier in the day (same session): multi-language selection was reworked — see
the **Language selection (fork feature)** section above for the design and the Parakeet
script-filter finding. Three things were wrong before this work and are now fixed:
the multi-select `LanguageSelectionView` had **zero call sites** since upstream's AI Models
page redesign (`8b63691`) and rendered for no model at all; local Whisper read the global
`UserDefaults["SelectedLanguages"]` in `LibWhisper.fullTranscribe` and ignored the Mode's
language entirely, so picking Russian silently transcribed English; and language lived only
as a single string. The orphaned view was deleted and its toggle logic moved into
`ModeConfigDraft.toggleLanguage`.

`make local-stable` is green on arm64 **and** on the Intel path
(`VOICEINK_TARGET_ARCH=x86_64`, verified in an earlier session), `VoiceInkTests` passes 76/76,
and the app is installed to `/Applications/VoiceInk.app` and running from that build.

Running the unit tests takes the same flags the local *app* build takes, not just
`-only-testing`. Unlike a plain `build`, `test` has to **launch** the host app, and it dies
before the harness connects under anything less:

```bash
./scripts/arch-xcodebuild.sh -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -destination 'platform=macOS' -only-testing:VoiceInkTests \
  -derivedDataPath build/test-dd -xcconfig LocalBuild.xcconfig \
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
build, failing the whole run for an unrelated reason.

**Always build with `make local-stable`, never plain `make local`** — ad-hoc signing has no
stable code identity, so every reinstall changes the cdhash, macOS drops its TCC grants, and
the app launches fine while silently ignoring the recording hotkey. Details in
`COMMON-ISSUES.md` §12b and `BUILDING.md`.

Next steps / open questions:
- **Not verified at runtime**: dictate a mixed ru/en/el phrase on Parakeet V3, confirm the
  `Languages` menu renders with the multi-script caption, and reopen the Mode after an app
  restart to confirm the selection persisted.
- Known limitation, deliberately out of scope: realtime Parakeet goes through
  `StreamingTranscriptionProvider.connect(model:language:)`, which takes one locale, so a
  same-script multi-selection (e.g. `ru + uk`) degrades to auto there while the batch path
  keeps the cyrillic filter. No effect on mixed-script selections. Fixing it means widening
  that protocol to `[String]` across ~10 providers.
- Local commits are unpushed by design — check `git log origin/main..main` and push with
  `--force-with-lease` (history is rebased, so a plain push is rejected).
- `dotfiles_private` has 2 unpushed commits from earlier work (`ece8417`, `f3a5b5c`).
- **Next task, and the only known rough edge: the first word is lost if the speaker does not
  pause after the wake word.** `f7a9f9a` cut the worst of it — `firstPartialSamples` was
  32_000 (2 s), so with no VAD speech-end event nothing was transcribed and recording had not
  started yet; it is 12_000 (0.75 s) now. **That change is committed and installed but was
  never observed working** — the user was asked to test and the session ended first. Verify
  before doing anything else. The residual gap is irreducible by tuning: the word must be
  spoken, recognised, and the recorder started. The complete fix is a pre-roll, handing the
  detector's own buffered audio to the recording, which means reaching into how `Recorder`
  writes its WAV. Offered to the user, not started.
- Also unverified, carried over: unplug → "not connected" warning with the built-in mic NOT
  taken; replug into a *different* port → rebinds by itself.
- Worth watching now that the detector holds the microphone through a recording: two AUHAL
  clients on the same device at once (its `CoreAudioRecorder` plus the dictation one). It
  built and ran, but no one has yet confirmed the dictation audio is unaffected.
- Parakeet transcribes any speech the VAD lets through, including audio from the speakers —
  seen in the log during testing. No false triggers were produced, but a wake word that is a
  common word would behave much worse than "лошадка".
- The user's `prioritizedDevices` still lists the same physical USB mic three times under
  three UIDs, a manual workaround for the bug `daf5f7e` fixed in `getCurrentDevice()`.
  Two of those entries can now be deleted — worth offering.
- Optional cleanup: `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/`
  still contains a junk `__MACOSX/` dir from an old unzip - safe to `rm -rf`.

## Repository State

After successful build, your fork should have:
- Multiple languages selector enabled
- No trial/buy banners
- All licensing checks returning "licensed"
- Local-only storage (no CloudKit)
