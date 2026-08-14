# Common Issues on Fresh macOS Installations

This document predicts and documents common issues that users may encounter when building and running VoiceInk on a fresh macOS installation.

## Build-Time Issues

### 1. Rosetta 2 Not Installed (Apple Silicon Macs)

**Likelihood**: High on brand new M1/M2/M3 Macs

**Symptoms**:
- Build fails with architecture-related errors
- Error: "Bad CPU type in executable"
- Some build tools fail to run

**Why it happens**: Some build dependencies may still require Rosetta 2 for Intel binary compatibility.

**Solution**:
```bash
# Install Rosetta 2
softwareupdate --install-rosetta --agree-to-license

# Verify installation
pgrep oahd
```

---

### 2. Xcode License Not Accepted

**Likelihood**: Very High on first Xcode installation

**Symptoms**:
- `xcodebuild` command fails
- Error: "Xcode license needs to be accepted"
- Build hangs or fails immediately

**Why it happens**: Xcode requires accepting the license agreement after installation.

**Solution**:
```bash
# Accept license via command line
sudo xcodebuild -license accept

# Or open Xcode and accept interactively
open /Applications/Xcode.app
```

---

### 3. Command Line Tools Wrong Version

**Likelihood**: Medium - especially after macOS updates

**Symptoms**:
- Build succeeds but produces warnings
- `xcode-select` points to wrong location
- Git or other tools behave unexpectedly

**Why it happens**: Multiple Xcode versions or standalone CLT installed.

**Solution**:
```bash
# Check current path
xcode-select -p

# Should show: /Applications/Xcode.app/Contents/Developer
# If not, reset it:
sudo xcode-select --reset
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

# Verify
xcodebuild -version
```

---

### 4. Insufficient Memory During whisper.cpp Build

**Likelihood**: Medium on Macs with 8GB RAM

**Symptoms**:
- `./build-xcframework.sh` fails or hangs
- System becomes unresponsive
- Error: "clang: error: unable to execute command: Killed"

**Why it happens**: Building whisper.xcframework for multiple architectures is memory-intensive.

**Solution**:
```bash
# Close other applications
# Monitor memory during build:
top -o MEM

# If build fails, try building with fewer parallel jobs
# Edit ../voiceink_dependencies/whisper.cpp/build-xcframework.sh
# Find lines with "cmake --build" and add: -- -j2
# (Limits to 2 parallel jobs instead of all cores)
```

---

### 5. Git Not Configured

**Likelihood**: High on first-time developer setups

**Symptoms**:
- Git clone works but warnings appear
- Submodule operations fail

**Why it happens**: Git needs basic configuration for some operations.

**Solution**:
```bash
# Set basic git config
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

---

### 6. Network Firewall Blocking SPM Downloads

**Likelihood**: Medium in corporate/school environments

**Symptoms**:
- Swift Package Manager hangs during package resolution
- Timeout errors when downloading dependencies
- Error: "Cannot connect to github.com"

**Why it happens**: Corporate firewalls may block git:// protocol or certain ports.

**Solution**:
```bash
# Configure git to use HTTPS instead of git://
git config --global url."https://github.com/".insteadOf git://github.com/

# Or configure proxy if needed
git config --global http.proxy http://proxy.example.com:8080
```

---

## Runtime Issues (After Building)

### 7. macOS Privacy & Security Permissions Required

**Likelihood**: 100% guaranteed on first run

**Critical Permissions Needed**:

#### Microphone Access
- **Required**: Yes
- **Why**: Voice recording for transcription
- **Prompt**: Automatic on first recording attempt
- **Manual**: System Settings → Privacy & Security → Microphone → Enable VoiceInk

#### Accessibility Access
- **Required**: Yes
- **Why**: Reading selected text, simulating keyboard events, detecting active applications
- **Prompt**: VoiceInk will show instructions
- **Manual**: System Settings → Privacy & Security → Accessibility → Enable VoiceInk

#### Screen Recording Permission
- **Required**: Yes (for context-aware features)
- **Why**: Capturing screen content for AI context
- **Prompt**: Automatic when feature is used
- **Manual**: System Settings → Privacy & Security → Screen Recording → Enable VoiceInk

**Important**: The app **will not work properly** until all permissions are granted. Users should be prepared to grant these on first launch.

---

### 8. "VoiceInk.app is damaged and can't be opened"

**Likelihood**: High when building locally without code signing

**Symptoms**:
- App builds successfully but won't open
- macOS shows "damaged" warning
- Error about security or quarantine

**Why it happens**: macOS Gatekeeper quarantines unsigned apps.

**Solution**:
```bash
# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "VoiceInk.app" -type d | head -1)

# Remove quarantine attribute
xattr -cr "$APP_PATH"

# Or allow the app in System Settings
# System Settings → Privacy & Security → "Open Anyway"
```

**Prevention**: The Makefile builds with `CODE_SIGN_IDENTITY=""` which should avoid this, but if it happens, use the solution above.

---

### 9. Audio Input Device Not Detected

**Likelihood**: Low but possible with USB/Bluetooth mics

**Symptoms**:
- Recording fails silently
- No audio captured
- Microphone permission granted but still no recording

**Why it happens**: Audio device switching, permissions not applied to specific device.

**Solution**:
```bash
# Check audio devices
system_profiler SPAudioDataType

# Restart audio services
sudo killall coreaudiod

# Verify microphone in System Settings → Sound → Input
# Select the correct input device
```

---

### 10. Keyboard Shortcuts Conflict

**Likelihood**: Medium - depends on user's installed apps

**Symptoms**:
- Global shortcuts don't work
- Shortcuts trigger wrong app
- No response when pressing configured shortcut

**Why it happens**: Other apps may be using the same shortcut combinations.

**Solution**:
- Configure different shortcuts in VoiceInk settings
- Check System Settings → Keyboard → Keyboard Shortcuts for conflicts
- Disable conflicting shortcuts in other apps

---

### 11. Models Not Downloaded or Missing

**Likelihood**: Medium if building from source

**Symptoms**:
- Transcription fails
- Error about missing model files
- App crashes when trying to transcribe

**Why it happens**: VoiceInk needs AI models for transcription. The bundled app includes these, but building from source may not.

**Expected model location**: `VoiceInk/Resources/models/`

**Check**:
```bash
ls -lh VoiceInk/Resources/models/
# Should see: ggml-silero-v5.1.2.bin (and potentially whisper models)
```

**Solution**:
- Models should be included in the repository
- If missing, check git LFS (Large File Storage) is installed
- Some models may need manual download

---

### 12. Accessibility Access Lost After macOS Update

**Likelihood**: Medium after major macOS updates (e.g., 14.0 → 15.0)

**Symptoms**:
- VoiceInk worked before but stops after update
- Cannot paste text or detect selected text
- Permissions show as granted but features don't work

**Why it happens**: macOS sometimes resets accessibility permissions after major updates.

**Solution**:
```bash
# Reset accessibility permissions
# System Settings → Privacy & Security → Accessibility
# 1. Remove VoiceInk from the list (click - button)
# 2. Add it back (click + button, navigate to VoiceInk.app)
# 3. Restart VoiceInk
```

---

### 12b. Hotkey Silently Stops Working After a Local Rebuild

**Likelihood**: Every rebuild, if you build with `make local` instead of `make local-stable`

**Symptoms**:
- The app launches normally and looks completely healthy — no crash, no error dialog
- Pressing the recording hotkey does **nothing at all**
- `pgrep -x VoiceInk` shows the process alive, so it reads like a hotkey bug, not a permissions bug
- Started right after a rebuild / reinstall (including an automated nightly one)

**Why it happens**: macOS pins every TCC grant to the **leaf certificate** the bundle was signed with, and stores that as a code requirement:

```
identifier "com.prakashjoshipax.VoiceInk" and certificate leaf = H"909602ca…"
```

When the installed bundle no longer satisfies it, `tccd` does not prompt and does not warn — it just refuses:

```
tccd  Failed to match existing code requirement for subject
      com.prakashjoshipax.VoiceInk and service kTCCServiceListenEvent
```

Two different mistakes produce that line:

- **`make local`** signs ad-hoc (`LOCAL_SIGN_IDENTITY = -`), which has no stable identity at all — every reinstall is a new app to macOS. `make local` now refuses to overwrite a stably-signed install unless you pass `FORCE_ADHOC=1`.
- **A regenerated `VoiceInk Local Signing` certificate**, which is just as fatal and far less obvious. Deleting the cert and letting `create-local-signing-cert.sh` recreate it — the documented cure for an orphaned keychain entry — produces a *new* leaf hash, so the old grants keep pointing at a certificate that no longer exists. The script now prints a loud warning whenever it creates a certificate.

The hotkey needs Accessibility (and Input Monitoring for hold-to-talk / hybrid mode), so it goes dead while transcription over the CLI keeps working perfectly — the CLI path never touches key events, which is what makes this read like a hotkey bug rather than a permissions bug.

**Diagnosis**:

```bash
make check-tcc
```

It prints the installed bundle's `Authority=` and any requirement mismatch `tccd` logged in the last 15 minutes.

**Solution** — fix the cause, then re-grant once:

```bash
# 1. Rebuild with a stable self-signed identity
make local-stable

# 2. Confirm the bundle is no longer ad-hoc  (-dv is not enough, Authority needs -dvvv)
codesign -dvvv /Applications/VoiceInk.app 2>&1 | grep Authority
#    want: Authority=VoiceInk Local Signing

# 3. Drop the stale grants — they point at the OLD certificate
osascript -e 'quit app "VoiceInk"'
for s in ListenEvent Accessibility Microphone ScreenCapture; do
    tccutil reset $s com.prakashjoshipax.VoiceInk
done

# 4. Relaunch and grant what macOS asks for
open -a VoiceInk
```

**Then quit and reopen VoiceInk again.** A grant issued while the app is running does not reach it: the process built its event tap at launch, when it still had no permission, and nothing rebuilds it. Skipping this step is why the hotkey often still looks broken right after you flip the switch in System Settings.

If a stale entry survives in System Settings → Privacy & Security → Accessibility / Input Monitoring, remove it with `−` before granting again, otherwise the system holds on to the old record.

**If the identity looks missing, check twice before touching it.** `security find-identity -v` does **not** list this certificate: `-v` means "valid identities only" and a self-signed cert is `CSSMERR_TP_NOT_TRUSTED`. Without `-v` it appears under *Matching identities* and signs perfectly well. Prove it with the only test that matters:

```bash
security find-identity -p codesigning | grep "VoiceInk Local"   # expect CSSMERR_TP_NOT_TRUSTED — fine
cp /bin/echo /tmp/sigtest && codesign --force --sign "VoiceInk Local Signing" /tmp/sigtest
```

If that signs, nothing is wrong. **Do not run `create-local-signing-cert.sh` to "fix" it** — that script deletes the certificate and mints a new one, which is a new Designated Requirement, which drops every TCC grant you are trying to preserve. `make local-stable` calls it, which is why unattended builds must use `make local LOCAL_SIGN_IDENTITY=<sha1>` instead.

If codesign genuinely fails, restore the key from the backup rather than minting a new one:

```bash
security import ~/.config/voiceink/local-signing.p12 \
  -k ~/Library/Keychains/login.keychain-db -P voiceink-local -T /usr/bin/codesign
```

Only when there is no backup and no working key is `./scripts/create-local-signing-cert.sh` the answer — and then every permission has to be granted again by hand.

---

### 13. AppleScript/Automation Permissions for Browser Integration

**Likelihood**: High when using Power Mode with browser detection

**Symptoms**:
- Browser URL detection doesn't work
- Error: "Not authorized to send Apple events"
- Power Mode features fail

**Why it happens**: VoiceInk uses AppleScript to get browser URLs, requires Automation permission.

**Solution**:
- System Settings → Privacy & Security → Automation
- Ensure VoiceInk has permission to control:
  - Safari
  - Chrome (if used)
  - Firefox (if used)
  - Other browsers you use

---

### 14. Metal GPU Support Issues

**Likelihood**: Low on modern Macs, higher on older Intel Macs

**Symptoms**:
- Transcription very slow
- High CPU usage during transcription
- Warnings about Metal not available

**Why it happens**: whisper.cpp uses Metal for GPU acceleration. Older Macs may have limited Metal support.

**Check**:
```bash
# Check Metal support
system_profiler SPDisplaysDataType | grep -i metal
```

**Solution**:
- Ensure macOS is up to date (Metal support improves with updates)
- On older Macs, transcription will work but be slower (CPU-only)
- Consider upgrading macOS if on older version

---

### 15. iCloud/CloudKit Entitlements Issues

**Likelihood**: Low (mainly affects distributed builds)

**Symptoms**:
- App launches but iCloud sync doesn't work
- Warnings about iCloud container access
- Settings don't sync across devices

**Why it happens**: The app uses CloudKit for syncing (see VoiceInk.entitlements), but locally built apps won't have proper iCloud provisioning.

**Impact**: Non-critical - app works fine, just no sync features.

**Solution**:
- For personal use: Ignore - sync features won't work but everything else will
- For distribution: Need proper Apple Developer account and provisioning profile

---

## Environment-Specific Issues

### 16. Homebrew Conflicts

**Likelihood**: Medium if user has Homebrew with development tools

**Symptoms**:
- Build uses wrong version of tools
- Linker errors about library versions
- Conflicts between system and Homebrew libraries

**Why it happens**: Homebrew may install its own versions of build tools that conflict with Xcode's.

**Solution**:
```bash
# Temporarily prioritize Xcode tools
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

# Or unset Homebrew from PATH during build
brew unlink cmake # if installed
make all
brew link cmake # restore after
```

---

### 17. Case-Sensitive File System Issues

**Likelihood**: Very Low (most users have case-insensitive)

**Symptoms**:
- File not found errors during build
- Inconsistent file references

**Why it happens**: macOS default is case-insensitive (APFS), but some users format as case-sensitive.

**Check**:
```bash
diskutil info / | grep "File System Personality"
```

**Solution**: The project should work on case-sensitive systems, but if issues occur, check file name capitalization in imports.

---

### 18. macOS Beta/Developer Seed Issues

**Likelihood**: Medium for users on beta macOS

**Symptoms**:
- Xcode compatibility issues
- Runtime crashes on new macOS beta
- API deprecation warnings

**Why it happens**: Beta macOS may have API changes not yet supported.

**Solution**:
- Use latest Xcode beta with macOS beta
- Report issues as incompatible with beta (expected)
- Stick to stable macOS for production builds

---

### 19. Build dies on mlx-swift's plugin, its macro, or a missing Metal toolchain

**Likelihood**: Certain on Xcode 16 and newer, including after a routine Xcode upgrade

**Symptoms**: the build never reaches a single Swift file and stops at one of

```
Plugin "CudaBuild" from package "mlx-swift" must be enabled before it can be used
Macro "MLXHuggingFaceMacros" from package "mlx-swift-lm" must be enabled before it can be used
error: cannot execute tool 'metal' due to missing Metal Toolchain
```

**Why it happens**: Xcode will not run an untrusted package plugin or macro, and only offers
the trust prompt in the GUI — a command-line build has no way to answer it. Separately,
Xcode 26 stopped bundling the Metal toolchain that mlx-swift's shaders need, so an Xcode
upgrade breaks a repo that built fine the day before.

**Solution**: the two flags live in `XCB_FLAGS` in the Makefile and in
`scripts/release.sh`, so `make build`, `make local-stable` and `make release` are covered.
Anything hand-rolled needs them spelled out:

```bash
xcodebuild ... -skipPackagePluginValidation -skipMacroValidation
```

The toolchain is a one-time download:

```bash
xcodebuild -downloadComponent MetalToolchain
```

---

### 20. An unattended build hangs while resolving packages

**Likelihood**: certain for a scheduled build, every time upstream adds or bumps a
binary artifact (`TranscribeCpp`, `NemoTextProcessing`, `Sparkle`)

**Symptoms**: `xcodebuild` sits at `Resolve Package Graph` forever. A sample of the
process shows the wait, and nothing in the log says why:

```
Workspace.BinaryArtifactsManager.download(artifact:destination:progress:)
  HTTPClient.execute(_:observabilityScope:progress:)
    CompositeAuthorizationProvider.authentication(for:)
      KeychainAuthorizationProvider.get(protocolHostPort:created:modified:)
        SecItemCopyMatching → CSSM_DecryptDataFinal → mach_msg
```

**Why it happens**: before downloading a binary artifact, SwiftPM asks for
credentials for its host in the order `~/.netrc` → login keychain. With no
`github.com` line in netrc it falls through to the keychain item `github.com`,
whose partition list holds only `git-credential-osxkeychain` — so reading it needs
authorization. In a session with a GUI that is a dialog; unattended at 04:15 nobody
clicks it and the build waits forever.

The confusing part is that the same command run from a **background** session (a
launchd job with no Aqua session, `launchctl managername` = `Background`) succeeds:
no GUI is possible, so securityd fails the query immediately instead of prompting,
and SwiftPM carries on without credentials — the asset is public and needs none.
So the failure appears only where it hurts.

**Solution**: give netrc the answer so the keychain is never consulted.

```bash
printf 'machine github.com\n    login <user>\n    password %s\n' "$(gh auth token)" >> ~/.netrc
chmod 600 ~/.netrc
```

`git-credential-osxkeychain` rewrites the keychain item and resets its partition
list whenever the token refreshes, so blessing the item instead of using netrc does
not stay fixed.

---

### 21. `test` dies on `Assertion failed: childPID > 0` before any test runs

**Likelihood**: certain when `xcodebuild test` is started from a background session

**Symptoms**:

```
DVTAssertions: ASSERTION FAILURE in IDELaunchServicesLauncher.m:418
Details:  Assertion failed: childPID > 0
Testing started
Abort trap: 6
```

**Why it happens**: the unit tests are hosted by the app, so the runner has to
*launch* it through LaunchServices — which only reports a PID inside the user's Aqua
session. From a background session it returns `procNotFound` and the launcher
aborts. The check that separates this from a real bug is one line:

```bash
launchctl managername      # "Aqua" → tests can run; "Background" → they cannot
open -W -n /Applications/VoiceInk.app
# background session: Unable to block on application (GetProcessPID() returned …)
```

The app itself is fine — running its binary directly works, and the same `open -W`
fails against a known-good installed build.

**Solution**: run the tests from a terminal in the logged-in session, or from a
LaunchAgent in `gui/$UID` (which is where the nightly sync runs — see
`dotfiles/cron/scripts/voiceink-upstream-sync.sh`). A crashed run orphans its test
host, and that leftover instance breaks the *next* run the same way, so kill it:

```bash
pkill -9 -f '.local-build-test/Build/Products/Debug/VoiceInk.app/Contents/MacOS'
```

---

## Prevention Best Practices

### Before Building

```bash
# 1. Verify system meets requirements
./check-build-env.sh

# 2. Accept Xcode license
sudo xcodebuild -license accept

# 3. Verify Command Line Tools
xcode-select --install  # Will say "already installed" if present

# 4. Check available disk space (need 5GB+)
df -h .

# 5. Check internet connection
ping -c 1 github.com

# 6. Clean build environment
make clean
```

### After Building

```bash
# 1. Remove quarantine
xattr -cr ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/VoiceInk.app

# 2. Prepare to grant permissions on first launch
# - Microphone
# - Accessibility
# - Screen Recording
# - Automation (for browsers)
```

---

## Getting Help

If you encounter issues not covered here:

1. Run `./check-build-env.sh` and include output
2. Check build logs: `xcodebuild ... > build.log 2>&1`
3. Check runtime logs: `Console.app` → Filter for "VoiceInk"
4. Search [GitHub Issues](https://github.com/Beingpax/VoiceInk/issues)
5. Create new issue with:
   - macOS version (`sw_vers`)
   - Xcode version (`xcodebuild -version`)
   - Output from `./check-build-env.sh`
   - Complete error messages
   - Steps to reproduce

---

## Quick Reference: First Build Checklist

- [ ] macOS 14.0+ installed
- [ ] Xcode 15.0+ installed from Mac App Store
- [ ] Xcode license accepted: `sudo xcodebuild -license accept`
- [ ] Command Line Tools installed: `xcode-select --install`
- [ ] At least 5GB free disk space
- [ ] Internet connection active
- [ ] Git configured: `git config --global user.name "..."`
- [ ] Run: `./check-build-env.sh`
- [ ] Run: `make all`
- [ ] On first launch, grant all permissions when prompted
