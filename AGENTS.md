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

`WakeWordListeningService` runs `SFSpeechRecognizer` over an `AVAudioEngine` input tap and
posts `.toggleRecorderPanel` when it hears the wake word. Six defects were found and fixed
in the 2026-07-25 session; the notes below are what makes the design non-obvious.

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
always-on listener and stream the room to Apple continuously.

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

Tests: `VoiceInkTests/WakeWordDetectionTests.swift`.

## Handoff

Current state (2026-07-25, later session): multi-language selection was reworked — see
the **Language selection (fork feature)** section above for the design and the Parakeet
script-filter finding. Three things were wrong before this work and are now fixed:
the multi-select `LanguageSelectionView` had **zero call sites** since upstream's AI Models
page redesign (`8b63691`) and rendered for no model at all; local Whisper read the global
`UserDefaults["SelectedLanguages"]` in `LibWhisper.fullTranscribe` and ignored the Mode's
language entirely, so picking Russian silently transcribed English; and language lived only
as a single string. The orphaned view was deleted and its toggle logic moved into
`ModeConfigDraft.toggleLanguage`.

`make local-stable` is green on arm64 **and** on the Intel path
(`VOICEINK_TARGET_ARCH=x86_64`, verified in an earlier session), `VoiceInkTests` passes 51/51,
and the app is installed to `/Applications/VoiceInk.app` and running from that build.

Run the unit tests with `-only-testing:VoiceInkTests`. A plain `test` also builds
`VoiceInkUITests`, whose runner is rejected by Gatekeeper ("VoiceInkUITests-Runner is
damaged") under the local unsigned build, failing the whole run for an unrelated reason.

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
- **Wake word still needs a runtime pass with the USB mic physically attached** (it was not
  connected during the fix session, so only the code paths were verified). Check: the status
  card names the bound device; unplug → "not connected" warning and the built-in mic is NOT
  taken; replug into a *different* port → rebinds on its own; dictate three times in a row →
  listening resumes each time; leave it 15 min silent → still triggers. Watch
  `log stream --predicate 'subsystem == "com.prakashjoshipax.voiceink" AND category == "WakeWordListeningService"'`
  and confirm `onDevice recognition: true` for `ru-RU` — if it logs `false`, the on-device
  asset never downloaded and the ~1 min server cap still applies.
- Optional cleanup: `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/`
  still contains a junk `__MACOSX/` dir from an old unzip - safe to `rm -rf`.

## Repository State

After successful build, your fork should have:
- Multiple languages selector enabled
- No trial/buy banners
- All licensing checks returning "licensed"
- Local-only storage (no CloudKit)
