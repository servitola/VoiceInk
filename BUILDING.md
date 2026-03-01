# Building VoiceInk

This guide provides detailed instructions for building VoiceInk from source on **macOS only**. VoiceInk is a macOS-exclusive application and does not support iOS or other platforms.

## Prerequisites

Before you begin, ensure you have the following installed:

### Required Software

1. **macOS 14.0 or later**
   - Check your version: `sw_vers`
   - VoiceInk requires macOS Sonoma or newer

2. **Xcode 15.0 or later**
   - Download from the Mac App Store or [Apple Developer](https://developer.apple.com/xcode/)
   - Check your version: `xcodebuild -version`
   - **Important**: Install the full Xcode application, not just Command Line Tools

3. **Xcode Command Line Tools**
   - Install with: `xcode-select --install`
   - Verify installation: `xcode-select -p`
   - This is required for git, xcodebuild, and other build tools

4. **Git**
   - Usually installed with Xcode Command Line Tools
   - Verify: `git --version`

### System Requirements

- **Platform**: macOS only (not iOS, iPadOS, or other Apple platforms)
- **Architecture**: Apple Silicon (M1/M2/M3) or Intel
- **Disk Space**: At least 5GB free for dependencies and build artifacts
- **Memory**: 8GB RAM minimum, 16GB recommended for faster builds

## Quick Start (TL;DR)

If you just want to build and run VoiceInk quickly:

```bash
# 1. Install Xcode from Mac App Store (if not already installed)
# 2. Install Command Line Tools
xcode-select --install

# 3. Clone the repository
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk

# 4. (Optional) Check your build environment
./check-build-env.sh

# 5. Build everything
make all

# 6. Run the app
make run
```

That's it! The Makefile handles everything including building the whisper.cpp dependency.

**Note**: If you encounter build errors about missing headers (e.g., `ggml-cpu.h file not found`), see the [Known Issues](#known-issues) section below for a quick fix. If you have other issues, run `./check-build-env.sh` to verify your system meets all requirements, then check the [Troubleshooting](#troubleshooting) section or consult [COMMON-ISSUES.md](COMMON-ISSUES.md).

---

## Quick Start with Makefile (Recommended)

The easiest way to build VoiceInk is using the included Makefile, which automates the entire build process including building and linking the whisper framework.

### Simple Build Commands

```bash
# Clone the repository
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk

# Build everything (recommended for first-time setup)
make all

# Or for development (build and run)
make dev
```

### Available Makefile Commands

- `make check` or `make healthcheck` - Verify all required tools are installed
- `make whisper` - Clone and build whisper.cpp XCFramework automatically
- `make setup` - Prepare the whisper framework for linking
- `make build` - Build the VoiceInk Xcode project
- `make local` - Build for local use (no Apple Developer certificate needed)
- `make run` - Launch the built VoiceInk app
- `make dev` - Build and run (ideal for development workflow)
- `make all` - Complete build process (default)
- `make clean` - Remove build artifacts and dependencies
- `make help` - Show all available commands

### How the Makefile Helps

The Makefile automatically:
1. **Manages Dependencies**: Creates a dedicated `~/VoiceInk-Dependencies` directory for all external frameworks
2. **Builds Whisper Framework**: Clones whisper.cpp and builds the XCFramework with the correct configuration
3. **Handles Framework Linking**: Sets up the whisper.xcframework in the proper location for Xcode to find
4. **Verifies Prerequisites**: Checks that git, xcodebuild, and swift are installed before building
5. **Streamlines Development**: Provides convenient shortcuts for common development tasks

This approach ensures consistent builds across different machines and eliminates manual framework setup errors.

### Dependencies

VoiceInk has several dependencies that are automatically managed:

- **Swift Package Manager** handles most dependencies automatically (FluidAudio, KeyboardShortcuts, LaunchAtLogin, Sparkle, etc.)
- **whisper.xcframework** is the only dependency requiring manual building (automated by Makefile)

For a complete list of dependencies, see [DEPENDENCIES.md](DEPENDENCIES.md).

---

## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
make local
open ~/Downloads/VoiceInk.app
```

This builds VoiceInk with ad-hoc signing using a separate build configuration (`LocalBuild.xcconfig`) that requires no Apple Developer account.

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `VoiceInk.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `LOCAL_BUILD` Swift compilation flag for conditional code paths

Your normal `make all` / `make build` commands are completely unaffected.

---

## Manual Build Process (Alternative)

If you prefer to build manually or need more control over the build process, follow these steps:

### Building whisper.cpp Framework

1. Clone and build whisper.cpp:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```
This will create the XCFramework at `build-apple/whisper.xcframework`.

### Building VoiceInk

1. Clone the VoiceInk repository:
```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
```

2. Add the whisper.xcframework to your project:
   - Drag and drop `../whisper.cpp/build-apple/whisper.xcframework` into the project navigator, or
   - Add it manually in the "Frameworks, Libraries, and Embedded Content" section of project settings

3. Build and Run
   - Build the project using Cmd+B or Product > Build
   - Run the project using Cmd+R or Product > Run

## Known Issues & Required Fixes

### 1. Whisper Framework Missing Headers (Required Step)

The whisper.cpp `build-xcframework.sh` script doesn't copy all required headers. **You must manually copy them after building whisper:**

```bash
# After make whisper completes, copy the headers
cp ~/VoiceInk-Dependencies/whisper.cpp/build-macos/framework/whisper.framework/Versions/A/Headers/*.h \
   ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Headers/

# Verify headers are present (should show 8 .h files)
ls ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Headers/
```

Without this step, you'll get: `ggml-cpu.h file not found` or `could not build Objective-C module 'whisper'`

### 2. macOS 26 API Compatibility (Already Fixed in Code)

VoiceInk includes experimental support for future macOS 26 Speech APIs. This code is disabled via conditional compilation in:
- `VoiceInk/Services/NativeAppleTranscriptionService.swift`
- `VoiceInk/Services/TranscriptionServiceRegistry.swift`

The app gracefully falls back to cloud transcription when native Apple transcription is requested. No action needed unless you're on an older commit.

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Ensure the whisper.xcframework is properly linked in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run the test suite before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

### Common Build Errors

#### Error: "whisper.xcframework not found"

**Cause**: The whisper framework hasn't been built or is in the wrong location.

**Solution**:
```bash
# Option 1: Use Makefile to rebuild whisper
make clean
make whisper

# Option 2: Manually verify the framework exists
ls -la ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework

# If missing, rebuild whisper.cpp
cd ~/VoiceInk-Dependencies/whisper.cpp
./build-xcframework.sh
```

#### Error: "Command Line Tools not found" or "xcodebuild: command not found"

**Cause**: Xcode Command Line Tools are not installed or not configured properly.

**Solution**:
```bash
# Install Command Line Tools
xcode-select --install

# If already installed, reset the path
sudo xcode-select --reset
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

# Verify installation
xcodebuild -version
```

#### Error: Building for iOS instead of macOS

**Cause**: Xcode is selecting the wrong SDK or platform. This is a common issue when AI tools or automated build systems try to configure the project.

**Important**: VoiceInk is **macOS-only**. It does not support iOS, iPadOS, or any other Apple platform.

**Solution**:
1. Open `VoiceInk.xcodeproj` in Xcode
2. Select the VoiceInk target
3. Go to Build Settings
4. Search for "Supported Platforms"
5. Verify it shows only `macosx` (NOT `iphoneos` or `iphonesimulator`)
6. Search for "Base SDK"
7. Ensure "Base SDK" is set to "macOS" (NOT iOS)
8. Go to General tab > Deployment Info
9. Confirm no iOS deployment targets are set
10. Clean and rebuild (Cmd+Shift+K, then Cmd+B)

Alternatively, use the Makefile which forces macOS-only builds:
```bash
make clean
make build
```

If you see any iOS-related settings in the Xcode project, they should be removed. The project should only target macOS.

#### Error: "No such module 'FluidAudio'" or other Swift Package dependencies

**Cause**: Swift Package Manager hasn't resolved dependencies.

**Solution**:
```bash
# In Xcode: File > Packages > Reset Package Caches
# Then: File > Packages > Resolve Package Versions

# Or from command line:
rm -rf ~/Library/Developer/Xcode/DerivedData
xcodebuild -resolvePackageDependencies -project VoiceInk.xcodeproj -scheme VoiceInk
```

#### Error: Code signing failures

**Solution**: Build without code signing:
```bash
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build
```

#### Error: Permission denied when running `./build-xcframework.sh`

**Cause**: Build script doesn't have execute permissions.

**Solution**:
```bash
cd ~/VoiceInk-Dependencies/whisper.cpp
chmod +x build-xcframework.sh
./build-xcframework.sh
```

#### Error: "ggml-cpu.h file not found" or "could not build Objective-C module 'whisper'"

**Cause**: The whisper.xcframework is missing required header files.

**Solution**: Copy headers from the macOS framework (built as part of `make whisper`):
```bash
cp ~/VoiceInk-Dependencies/whisper.cpp/build-macos/framework/whisper.framework/Versions/A/Headers/*.h \
   ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Headers/

# Verify (should show 8 .h files)
ls ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Headers/
```

#### Error: "cannot find 'SpeechTranscriber' in scope"

**Cause**: Code references future macOS 26 APIs not available in current Xcode.

**Solution**: Already fixed in the codebase. Update to latest:
```bash
git pull origin main
```

#### Build succeeds but app won't run

**Solution**: Remove quarantine attribute and launch:
```bash
xattr -cr ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/VoiceInk.app
open ~/Library/Developer/Xcode/DerivedData/*/Build/Products/Debug/VoiceInk.app
```

If macOS still blocks it: Right-click the app → select "Open" (or System Settings > Privacy & Security > "Open Anyway")

### General Build Tips

1. **Clean Build Folder**: If you encounter mysterious build errors, clean first:
   ```bash
   # In Xcode
   Cmd+Shift+K (Clean Build Folder)

   # Or command line
   make clean
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```

2. **Check Prerequisites**: Verify all requirements before building:
   ```bash
   make check
   ```

3. **Verify macOS and Xcode Versions**:
   ```bash
   sw_vers                # Should show macOS 14.0+
   xcodebuild -version    # Should show Xcode 15.0+
   ```

4. **Framework Search Paths**: The project expects whisper.xcframework at:
   ```
   ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework
   ```
   This path is configured using `$(HOME)` so it works across different user accounts.

5. **Architecture Issues**: If you get architecture-related errors, ensure you're building for your Mac's architecture:
   ```bash
   # Check your Mac's architecture
   uname -m
   # arm64 = Apple Silicon (M1/M2/M3)
   # x86_64 = Intel
   ```

### Getting Help

If you still encounter issues after trying the solutions above:

1. Check existing [GitHub Issues](https://github.com/Beingpax/VoiceInk/issues)
2. Create a new issue with:
   - Your macOS version (`sw_vers`)
   - Your Xcode version (`xcodebuild -version`)
   - Complete error messages
   - Steps you've already tried
   - Build logs if available

3. Provide build logs:
   ```bash
   # Generate detailed build log
   xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug build > build.log 2>&1
   ``` 