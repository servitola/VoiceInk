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

## Handoff

Current state (2026-07-25): fork is synced with upstream **2.0 (build 205)** and
`origin/main` is in sync (`0 0`). History was rewritten from 27 junk commits ("1",
"Build", "tests", "rebase fixes") into **10 clean commits** on top of upstream and
force-pushed; the source tree was verified byte-identical to the pre-cleanup tree
apart from two dropped build artifacts (`default.profraw`, the compiled
`VoiceInkCLI/voiceink` binary, both now gitignored). Build, `VoiceInkTests` and the
launch check are green, and the nightly cron ran end-to-end successfully once.

**Always build with `make local-stable`, never plain `make local`.** `make local`
defaults to ad-hoc signing, which has no stable code identity: every reinstall gives
the bundle a new cdhash, so macOS drops its TCC grants and the app keeps launching
fine while silently ignoring the recording hotkey. This bit us this session. The
keychain also had a `VoiceInk Local Signing` certificate **without its private key**
(visible to `find-certificate`, absent from `find-identity`), which made
`make local-stable` itself fail confusingly — deleted and recreated. Accessibility /
Input Monitoring / Microphone were re-granted to the new signature and the hotkey
works. Details in `COMMON-ISSUES.md` §12b and `BUILDING.md`.

Next steps / open questions:
- The cron leaves commits unpushed by design — check `git log origin/main..main`
  every so often and push with `--force-with-lease` (history is rebased, so a plain
  push will be rejected).
- `dotfiles_private` has 2 unpushed commits from this work (`ece8417`, `f3a5b5c`);
  never pushed, pending a go-ahead.
- Wake-word mic picker was never verified at runtime: enable wake word, pick a
  non-default mic, confirm it listens on that device.
- Minor UX edge: if a saved `wakeWordMicrophoneUID` device is unplugged, the picker
  renders blank (service still falls back to the app device). Could add an explicit
  "Same as Recording" fallback when the UID is missing.
- Optional cleanup: `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/`
  still contains a junk `__MACOSX/` dir from an old unzip - safe to `rm -rf`.

## Repository State

After successful build, your fork should have:
- Multiple languages selector enabled
- No trial/buy banners
- All licensing checks returning "licensed"
- Local-only storage (no CloudKit)
