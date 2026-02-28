# Sync Upstream & Rebuild

Fetch the original VoiceInk project changes from `github.com/main`, check if the `servitola` branch is behind, Fetch latest from `github.com`, then rebase our local changes on top if needed (preserving all custom logic), then rebuild even the version embedded didn't change(it doesn't mean the developer didn't change anything) and install locally without certificates. Push in the end if was rebased.

## Steps

### 1. Fetch upstream

```bash
git fetch github.com
```

### 2. Compare branches

Show upstream commits that are not in `servitola`:

```bash
git log --oneline servitola..github.com/main
```

If the output is empty, `servitola` is already up to date — check the installed version before deciding whether to rebuild (see step 2b).

### 2b. Check if installed version already matches

```bash
# Get upstream target version
UPSTREAM_VER=$(git show github.com/main:appcast.xml | grep -m1 "shortVersionString" | sed 's/.*>\(.*\)<.*/\1/')

# Get installed version (empty if not installed)
INSTALLED_VER=$(defaults read /Applications/VoiceInk.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "")

echo "Upstream: $UPSTREAM_VER  Installed: $INSTALLED_VER"
```

If `UPSTREAM_VER == INSTALLED_VER`, the correct version is already installed — **stop here**. No rebase, no rebuild, no reinstall needed.

Only continue to step 3 if the branch was behind (step 2 had output) **or** the installed version doesn't match upstream.

### 3. Rebase (don't merge) servitola onto github.com/main

```bash
git rebase github.com/main
```

This replays all `servitola` commits on top of the latest upstream. The custom commits are:

- remove trials/buying (touches LicenseViewModel, ContentView, LicenseManagementView, DashboardPromotionsSection, MetricsView)
- select multiple languages (touches UserDefaultsManager, LanguageSelectionView, LibWhisper, WhisperPrompt)
- don't type space when recording is empty (touches WhisperState.swift)
- wake word engine (touches Info.plist, TranscriptionOutputFilter, WakeWordListeningService, SettingsView, WakeWordSettingsView, WhisperState+UI, WhisperState+WakeWord, WhisperState, WAKE_WORD_PLAN.md)

### 4. Fix rebase conflicts

If conflicts occur during rebase, for each conflicted file:

1. Read the conflicted file with `<<<<<<<`/`=======`/`>>>>>>>` markers.
2. Keep the upstream changes AND the custom `servitola` logic — merge them manually.
3. Key rule: **never drop** these custom behaviors:
   - No trial/paywall UI in ContentView, LicenseManagementView, MetricsView
   - Multi-language selection in LanguageSelectionView and WhisperPrompt
   - Empty-recording space guard in WhisperState
   - Wake word engine files (WakeWordListeningService, WhisperState+WakeWord, WakeWordSettingsView)
4. After resolving each file: `git add <file>` then `git rebase --continue`
5. If a conflict is too complex: `git rebase --skip` only if the commit's intent is fully covered by upstream already.

### 5. Push the rebased branch to origin

```bash
git push origin servitola --force-with-lease
```

### 6. Bump version to match upstream release

Upstream doesn't always bump `MARKETING_VERSION` in `project.pbxproj` when tagging a release (only `appcast.xml`). Check the latest appcast version and update pbxproj manually:

```bash
# Find what version upstream released
git show github.com/main:appcast.xml | grep -m1 "shortVersionString"

# Find current version in project
grep "MARKETING_VERSION" VoiceInk.xcodeproj/project.pbxproj | head -2

# Bump if needed (example: 1.70 → 1.71 / 170 → 171)
sed -i '' 's/CURRENT_PROJECT_VERSION = 170;/CURRENT_PROJECT_VERSION = 171;/g; s/MARKETING_VERSION = 1.70;/MARKETING_VERSION = 1.71;/g' VoiceInk.xcodeproj/project.pbxproj
```

### 7. Rebuild whisper.xcframework (only if needed)

`make build` will skip whisper if `build-apple/whisper.xcframework` already exists. Rebuild whisper only when:
- `libwhisper` dylib is missing from the xcframework
- The app crashes at launch with `dyld: Library not loaded: @rpath/libwhisper.1.dylib`

#### Standard rebuild

```bash
rm -rf ~/VoiceInk-Dependencies/whisper.cpp/build-apple
cd ~/VoiceInk-Dependencies/whisper.cpp && ./build-xcframework.sh
```

#### Xcode 26+ / beta SDK workaround

On Xcode 26.x beta, cmake for macOS target places artifacts in `Release-iphonesimulator/` instead of `Release/`, causing the script to fail. Fix: configure cmake with an explicit sysroot **before** running the script:

```bash
# 1. Remove stale build dir
rm -rf ~/VoiceInk-Dependencies/whisper.cpp/build-macos

# 2. Configure with explicit macosx sysroot
cd ~/VoiceInk-Dependencies/whisper.cpp
cmake -B build-macos -G Xcode \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DBUILD_SHARED_LIBS=OFF \
  -DWHISPER_BUILD_EXAMPLES=OFF \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF \
  -DGGML_METAL_EMBED_LIBRARY=ON \
  -DGGML_BLAS_DEFAULT=ON \
  -DGGML_METAL=ON \
  -DGGML_NATIVE=OFF \
  -DGGML_OPENMP=OFF \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 \
  "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" \
  -DCMAKE_OSX_SYSROOT=macosx \
  -DWHISPER_COREML=ON \
  -DWHISPER_COREML_ALLOW_FALLBACK=ON \
  -S .

# 3. Build
cmake --build build-macos --config Release -- -quiet

# 4. Verify artifacts landed in Release/ (not Release-iphonesimulator/)
ls ~/VoiceInk-Dependencies/whisper.cpp/build-macos/src/Release/

# 5. Patch the build script to skip the macos cmake step (already done) and run the rest
sed -i '' \
  's|^rm -rf build-macos|# rm -rf build-macos  # skipped: already built|' \
  build-xcframework.sh
sed -i '' \
  's|echo "Building for macOS\.\.\.".*|echo "Building for macOS... (skipped: already built)"\n# cmake -B build-macos already done manually|' \
  build-xcframework.sh

# 6. Run the script to finish (iOS/tvOS/visionOS + xcframework assembly)
./build-xcframework.sh

# 7. Verify dylib is present
find ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework \
  -path "*/macos*" -name "whisper" | head -3
```

### 8. Check if rebuild is needed, then build VoiceInk

Before building, confirm the project version differs from the installed version (already verified in step 2b). If they already matched, you would have stopped earlier.



```bash
cd ~/projects/voiceink
make build
```

Check for `** BUILD SUCCEEDED **` at the end. If it fails with missing whisper headers, copy them:

```bash
cp ~/VoiceInk-Dependencies/whisper.cpp/build-macos/src/Release/Headers/*.h \
   ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Headers/ 2>/dev/null || true
make build
```

### 9. Kill old process, install to /Applications, and launch

```bash
# Kill any running instance
pkill -x VoiceInk 2>/dev/null; sleep 1

# Install to /Applications in-place (preserves macOS TCC permissions)
APP_PATH=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1)
xattr -cr "$APP_PATH"
rsync -a --delete "$APP_PATH/" /Applications/VoiceInk.app/

# Launch from /Applications
open /Applications/VoiceInk.app

# Verify it started
sleep 2
pgrep -x VoiceInk && echo "VoiceInk is running ✓" || echo "ERROR: VoiceInk did not start"
```

### 10. Verify version

```bash
defaults read /Applications/VoiceInk.app/Contents/Info.plist CFBundleShortVersionString
```

Should match the upstream release version.
