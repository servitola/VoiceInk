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
# Edit ~/VoiceInk-Dependencies/whisper.cpp/build-xcframework.sh
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
