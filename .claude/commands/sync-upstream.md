# Sync Upstream & Rebuild

Fetch upstream VoiceInk (`github.com/main` = `Beingpax/VoiceInk`), rebase our custom
commits on top if we're behind (preserving every custom behavior), then **build →
test → verify the app runs → and only then push**. Rebuild/reinstall even when the
version string didn't change — upstream ships fixes without bumping the version.

**Golden rule: never push a broken state.** Build, run the test suite, and confirm the
installed app actually launches *and stays up* BEFORE pushing. If any gate fails, stop
and fix — do not push.

## Working branch & remotes

- Our working branch is **`main`**, tracking **`origin/main`** (`origin` = `servitola/VoiceInk`).
  (The old `servitola` remote branch is stale — ignore it.)
- Upstream is **`github.com`** remote, branch **`github.com/main`** (`Beingpax/VoiceInk`).

Derive the branch instead of hardcoding:

```bash
cd ~/projects/voiceink
BR=$(git branch --show-current)          # normally "main"
echo "working branch: $BR"
```

## Steps

### 0. Preflight

```bash
git rerere enabled 2>/dev/null || git config rerere.enabled true   # reuse conflict resolutions on re-runs
git status --short                                                 # must be clean; stash/commit anything first
```

### 1. Fetch upstream

```bash
git fetch github.com
```

### 2. How far behind are we?

```bash
git log --oneline "$BR"..github.com/main            # upstream commits not in our branch
git rev-list --count "$BR"..github.com/main         # count
```

Empty output ⇒ no new upstream commits. Non-empty ⇒ we're behind and must rebase +
rebuild.

### 2b. Determine the target version (use pbxproj, NOT appcast)

`appcast.xml` **lags behind** the real release (e.g. appcast said `1.79` while the code
was already `2.0`). The reliable source is `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`
in **`project.pbxproj`**:

```bash
UPSTREAM_MARKETING=$(git show github.com/main:VoiceInk.xcodeproj/project.pbxproj | grep -m1 "MARKETING_VERSION" | sed 's/.*= *//; s/;//')
UPSTREAM_BUILD=$(git show github.com/main:VoiceInk.xcodeproj/project.pbxproj | grep -m1 "CURRENT_PROJECT_VERSION" | sed 's/.*= *//; s/;//')
INSTALLED_VER=$(defaults read /Applications/VoiceInk.app/Contents/Info.plist CFBundleShortVersionString 2>/dev/null || echo "")
echo "upstream marketing=$UPSTREAM_MARKETING build=$UPSTREAM_BUILD  installed=$INSTALLED_VER"
```

### 2c. Decide whether to proceed

Proceed with rebase + rebuild if **either**:
- step 2 shows we're behind (new upstream commits), **or**
- the installed version doesn't match `$UPSTREAM_MARKETING`, **or**
- the app isn't currently installed / doesn't launch.

**Only stop early** when ALL of these hold: not behind (step 2 empty) **and**
`INSTALLED_VER == UPSTREAM_MARKETING` **and** the installed app launches cleanly.
Matching version strings alone are NOT enough — this run we were 47 commits behind while
both sides read `2.0`.

### 3. Back up, then rebase (never merge)

```bash
git branch -f "backup/pre-rebase-$(git rev-parse --short $BR)" "$BR"   # safety net
git rebase github.com/main
```

This replays our custom commits on top of upstream. Get the live list of what we're
replaying (don't trust a stale hardcoded list):

```bash
git log --oneline github.com/main..$BR
```

Custom features that must survive (as of this writing):
- **remove trials/buying** — LicenseViewModel/ContentView/LicenseManagementView/MetricsView: no paywall, always licensed.
- **select multiple languages** — UserDefaultsManager/LanguageSelectionView/LibWhisper/WhisperPrompt: `selectedLanguages` set.
- **wake word engine** — TranscriptionOutputFilter/WakeWordListeningService/WakeWordSettingsView/WhisperState+WakeWord + `WAKE_WORD_PLAN.md`.
- **CLI bridge** — `CLIBridgeService`, wired in `VoiceInk.swift`; `make cli` / `VoiceInkCLI`.
- **WordReplacement unicode fix + tests** — `applyReplacements(to:rules:)` pure transform + `VoiceInkTests/WordReplacementServiceTests.swift`.
- **Show Menu Bar Icon toggle + window recovery** — SettingsView/MenuBarView/AppDelegate + `MenuBarManager.focusMainWindow`.
- **local-build stable codesigning** — `LocalBuild.xcconfig`, `VoiceInk.local.entitlements`, Makefile `local`/`fix-derived-app`.

### 4. Resolve conflicts (merge upstream + keep our behavior)

For each conflicted file: read it, keep upstream's changes AND our custom logic, then
`git add <file>` && `git rebase --continue`. After every batch, sanity-check there are no
leftover markers:

```bash
git grep -nE '^(<<<<<<<|=======|>>>>>>>|\|\|\|\|\|\|\|)' -- 'VoiceInk/**' || echo "no markers ✓"
```

**Recurring resolutions (high-value shortcuts):**
- **LicenseViewModel.swift** — our commit rewrote the whole file to a free-fork stub; on conflict just take our full version: `git checkout <our-branch-tip> -- VoiceInk/Models/LicenseViewModel.swift` (or keep the `=======`…`>>>>>>>` side).
- **LibWhisper.swift / WhisperPrompt.swift** — keep our `selectedLanguages` blocks; upstream's side is usually just whitespace/`SelectedLanguage`-single-language.
- **TranscriptionOutputFilter.swift** — keep upstream's improved `filter()` AND append our `removeWakeWord` + `levenshteinDistance`. (`logger` is defined at the top of our version.)
- **WordReplacementService.swift** — keep our `for rule in sortedRules { … rule.replacement }` refactor; upstream's `sortedReplacements`/`replacementText` would be undefined against our `rules:` signature.
- **VoiceInk.swift** — upstream periodically renames the migration API (e.g. `runIfNeeded` → `runStatsMigrationIfNeeded`, var `migrationTask` → `statsMigrationTask`). Keep **upstream's** call/var name (later code references it) AND re-add our `CLIBridgeService.shared.start(...)` line.
- **AppDelegate.swift / MenuBarManager / MenuBarView** — upstream keeps refactoring window presentation into `WindowManager` + `AppPresentationPolicy`. Our menu-bar recovery calls `menuBarManager.focusMainWindow()`. If upstream dropped that method, **re-add it to `MenuBarManager`** on top of the current API:
  ```swift
  func focusMainWindow() {
      activateForPresentedWindow(reason: "Focus Main Window")
      if WindowManager.shared.currentMainWindow() != nil {
          WindowManager.shared.showMainWindow()
      } else {
          WindowManager.shared.prepareForUserRequestedMainWindow()
          NotificationCenter.default.post(name: .showMainWindowRequested, object: nil)
      }
  }
  ```
  In the reopen handler, merge: our menu-bar-only recovery branch first, then upstream's non-menu-bar-only flow, then default `return true`.

Only `git rebase --skip` a commit if upstream already fully covers its intent.

### 5. Bump version to match upstream (if pbxproj differs)

Usually upstream already bumped pbxproj (that's our source of truth in 2b), so this is a
no-op. Only if our pbxproj is behind upstream's:

```bash
grep -m2 -E "MARKETING_VERSION|CURRENT_PROJECT_VERSION" VoiceInk.xcodeproj/project.pbxproj
# sed -i '' 's/MARKETING_VERSION = 1.70;/MARKETING_VERSION = 1.71;/g; s/CURRENT_PROJECT_VERSION = 170;/CURRENT_PROJECT_VERSION = 171;/g' VoiceInk.xcodeproj/project.pbxproj
```

### 6. Build + install locally — use `make local`, NOT `make build`

**Do not use `make build` + rsync for the installed app.** That produces a Debug build
with the default entitlements (CloudKit enabled) which, when ad-hoc signed, **SIGTRAPs on
launch inside `NSCloudKitMirroringDelegate`** — the app appears to "not start". `make local`
compiles with `LOCAL_BUILD` (SwiftData CloudKit → `.none`) + `VoiceInk.local.entitlements`,
signs stably (TCC permissions persist), installs to `/Applications`, and adds the
`libwhisper.1.dylib` rpath symlink.

```bash
cd ~/projects/voiceink
make local
```

Expect `** BUILD SUCCEEDED **` and `Build complete! App installed to: /Applications/VoiceInk.app`.
If it fails on missing whisper headers/dylib, see the **whisper rebuild** appendix.

### 7. Test gate — all green before pushing

The unit tests are hosted by the app, so the host must also build with `LOCAL_BUILD` +
local entitlements, and needs the `libwhisper` rpath symlink (the test build dir doesn't
get it automatically — that missing symlink is exactly what makes the host crash at
bootstrap with `Library not loaded: @rpath/libwhisper.1.dylib`).

```bash
# Build the test host (LOCAL_BUILD avoids the CloudKit trap)
xcodebuild build-for-testing \
  -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath .local-build-test -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM="" \
  CODE_SIGN_ENTITLEMENTS="$(pwd)/VoiceInk/VoiceInk.local.entitlements" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) LOCAL_BUILD'

# Add the rpath symlink dyld needs (host embeds whisper.framework but not this link)
ln -sfn whisper.framework/Versions/A/whisper \
  .local-build-test/Build/Products/Debug/VoiceInk.app/Contents/Frameworks/libwhisper.1.dylib

# Run unit tests only (VoiceInkUITests drive a live app — skip in this gate)
xcodebuild test-without-building \
  -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
  -derivedDataPath .local-build-test -only-testing:VoiceInkTests \
  -destination 'platform=macOS'
```

Gate: exit 0 and every `Test case … passed`. If a test fails, it usually means a
conflict resolution was wrong (e.g. `WordReplacementService`) — fix the code, not the
test. (`.local-build-test/` is gitignored.)

### 8. Verify the installed app launches AND stays up

The CloudKit crash happened *after* launch, so check twice with a delay — a single
`pgrep` right after `open` isn't enough.

```bash
pkill -x VoiceInk 2>/dev/null; sleep 1
open /Applications/VoiceInk.app
sleep 5
pgrep -x VoiceInk >/dev/null && echo "running ✓" || echo "ERROR: not running"
```

If it isn't running, inspect the newest crash report and fix before proceeding:

```bash
CR=$(ls -t ~/Library/Logs/DiagnosticReports/VoiceInk*.ips | head -1)
python3 -c "import json,sys;raw=open('$CR').read().split(chr(10),1);b=json.loads(raw[1]);print(json.dumps(b.get('termination',{})))"
# Common causes: 'Library not loaded: @rpath/libwhisper.1.dylib' (rebuild whisper / re-run make local),
#                CloudKit SIGTRAP (you used make build instead of make local).
```

### 9. Push — only after build + tests + launch all passed

```bash
git push origin "$BR" --force-with-lease
```

Commit any API-adaptation fixes you made during conflict resolution (e.g. re-adding
`focusMainWindow`) as their own commit first, mirroring the existing
`fix: adapt … to upstream … API` style.

### 10. Verify version

```bash
defaults read /Applications/VoiceInk.app/Contents/Info.plist CFBundleShortVersionString
defaults read /Applications/VoiceInk.app/Contents/Info.plist CFBundleVersion
```

Should match `$UPSTREAM_MARKETING` / `$UPSTREAM_BUILD` from step 2b.

---

## Appendix: rebuild whisper.xcframework (only if needed)

`make local`/`make build` skip whisper when `build-apple/whisper.xcframework` already
exists. Rebuild only when the `libwhisper` dylib is missing from the xcframework or the
app crashes with `dyld: Library not loaded: @rpath/libwhisper.1.dylib` even after
re-running `make local`.

### Standard rebuild

```bash
rm -rf ../voiceink_dependencies/whisper.cpp/build-apple
cd ../voiceink_dependencies/whisper.cpp && ./build-xcframework.sh
```

### Xcode 26+ / beta SDK workaround

On Xcode 26.x beta, cmake for the macOS target places artifacts in
`Release-iphonesimulator/` instead of `Release/`, breaking the script. Configure cmake
with an explicit sysroot first:

```bash
rm -rf ../voiceink_dependencies/whisper.cpp/build-macos
cd ../voiceink_dependencies/whisper.cpp
cmake -B build-macos -G Xcode \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY="" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_EXAMPLES=OFF -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_SERVER=OFF -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_BLAS_DEFAULT=ON \
  -DGGML_METAL=ON -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 \
  "-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64" -DCMAKE_OSX_SYSROOT=macosx \
  -DWHISPER_COREML=ON -DWHISPER_COREML_ALLOW_FALLBACK=ON -S .
cmake --build build-macos --config Release -- -quiet
ls ../voiceink_dependencies/whisper.cpp/build-macos/src/Release/       # verify Release/, not Release-iphonesimulator/
sed -i '' 's|^rm -rf build-macos|# rm -rf build-macos  # skipped: already built|' build-xcframework.sh
sed -i '' 's|echo "Building for macOS\.\.\.".*|echo "Building for macOS... (skipped: already built)"|' build-xcframework.sh
./build-xcframework.sh
find ../voiceink_dependencies/whisper.cpp/build-apple/whisper.xcframework -path "*/macos*" -name "whisper" | head -3
```

If the app build later fails on missing whisper headers:

```bash
cp ../voiceink_dependencies/whisper.cpp/build-macos/src/Release/Headers/*.h \
   ../voiceink_dependencies/whisper.cpp/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Headers/ 2>/dev/null || true
```
