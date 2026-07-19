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

## Handoff

Current state (2026-07-18): Wake word now has a microphone selector.
Committed (not pushed): `feat(wake-word): add microphone selection`. Root
cause was `WakeWordListeningService` creating `AVAudioEngine().inputNode`,
which always binds to the system default input and ignored the app's mic
choice. Fix: `resolveInputDeviceID()` -> `inputNode.auAudioUnit.setDeviceID(...)`
before querying format/installing the tap; empty UID follows
`AudioDeviceManager.getCurrentDevice()` (same mic as recording). New
`configureMicrophone(uid:)` restarts listening on change; pass-through
`configureWakeWordMicrophone(uid:)` on VoiceInkEngine; Microphone picker
in WakeWordSettingsView persisting `wakeWordMicrophoneUID` (default
"Same as Recording"). `xcodebuild -scheme VoiceInk` compiles clean
(only signing fails without a provisioning profile). NOT verified in a
running app / with a rebuilt `.app`.

Next steps / open questions:
- Verify at runtime: enable wake word, pick a non-default mic, confirm it
  actually listens on that device (rebuild `/Applications/VoiceInk.app` via
  `make local-stable`).
- Minor UX edge: if a saved `wakeWordMicrophoneUID` device is unplugged, the
  picker renders blank (service still falls back to the app device). Could add
  an explicit "Same as Recording" fallback in the UI when the UID is missing.
- Optional cleanup: `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/`
  still contains a junk `__MACOSX/` dir from an old unzip - safe to `rm -rf`.

## Repository State

After successful build, your fork should have:
- Multiple languages selector enabled
- No trial/buy banners
- All licensing checks returning "licensed"
- Local-only storage (no CloudKit)
