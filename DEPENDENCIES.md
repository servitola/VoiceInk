# VoiceInk Dependencies

This document lists all dependencies required to build and run VoiceInk.

## System Requirements

### Operating System
- **macOS 14.0+** (Sonoma or newer)
- **Platform**: macOS only (not iOS, iPadOS, watchOS, or tvOS)

### Development Tools

| Tool | Minimum Version | Purpose | Installation |
|------|----------------|---------|--------------|
| Xcode | 15.0+ | IDE and build tools | Mac App Store |
| Xcode Command Line Tools | 15.0+ | Git, xcodebuild, compiler | `xcode-select --install` |
| Git | 2.0+ | Version control | Included with Command Line Tools |
| Swift | 5.9+ | Programming language | Included with Xcode |
| Make | Any | Build automation | Included with macOS |

## Framework Dependencies

### Native Framework (Manual Build Required)

#### whisper.xcframework
- **Repository**: https://github.com/ggerganov/whisper.cpp
- **Purpose**: High-performance speech-to-text transcription using OpenAI's Whisper model
- **Build Location**: `~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework`
- **Build Method**:
  ```bash
  # Automated via Makefile (recommended)
  make whisper

  # Or manual build
  git clone https://github.com/ggerganov/whisper.cpp.git
  cd whisper.cpp
  ./build-xcframework.sh
  ```
- **License**: MIT
- **Notes**: This is the only dependency that requires manual building. All others are managed by Swift Package Manager.

## Swift Package Dependencies

VoiceInk uses Swift Package Manager (SPM) for most dependencies. These are automatically downloaded and built by Xcode.

### Audio & Transcription

#### FluidAudio
- **Repository**: https://github.com/FluidInference/FluidAudio
- **Purpose**: Parakeet model implementation for speech recognition
- **Version**: main (latest)
- **Auto-resolved**: Yes

### User Interface & System Integration

#### KeyboardShortcuts
- **Repository**: https://github.com/sindresorhus/KeyboardShortcuts
- **Purpose**: User-customizable global keyboard shortcuts
- **Version**: 2.4.0
- **Auto-resolved**: Yes

#### LaunchAtLogin
- **Repository**: https://github.com/sindresorhus/LaunchAtLogin-Modern
- **Purpose**: Launch at login functionality
- **Version**: Latest
- **Auto-resolved**: Yes

#### SelectedTextKit
- **Repository**: https://github.com/tisfeng/SelectedTextKit
- **Purpose**: Modern macOS library for getting selected text
- **Version**: 2.6.2
- **Auto-resolved**: Yes
- **Dependencies**: Includes AXSwift (0.3.6) and KeySender

### System Control

#### MediaRemoteAdapter
- **Repository**: https://github.com/ejbills/mediaremote-adapter
- **Purpose**: Media playback control during recording (pause/resume)
- **Version**: Latest
- **Auto-resolved**: Yes

### Updates & Utilities

#### Sparkle
- **Repository**: https://github.com/sparkle-project/Sparkle
- **Purpose**: Automatic app updates
- **Version**: Latest
- **Auto-resolved**: Yes

#### Zip
- **Repository**: https://github.com/marmelroy/Zip
- **Purpose**: File compression and decompression utilities
- **Version**: 2.1.2
- **Auto-resolved**: Yes

### Low-Level Libraries

#### Swift Atomics
- **Repository**: https://github.com/apple/swift-atomics
- **Purpose**: Low-level atomic operations for thread-safe concurrent programming
- **Version**: 1.3.0
- **Auto-resolved**: Yes
- **Maintained by**: Apple

## Transitive Dependencies

These are dependencies of dependencies, automatically managed by SPM:

- **AXSwift** (0.3.6) - Required by SelectedTextKit for accessibility features
- **KeySender** - Required by SelectedTextKit for keyboard event simulation

## Dependency Resolution

### Automatic Resolution (Recommended)

Swift Package Manager handles all dependencies except whisper.xcframework:

```bash
# Using Makefile (builds whisper + resolves SPM packages)
make all

# Or in Xcode
File > Packages > Resolve Package Versions
```

### Manual Resolution

If you encounter package resolution issues:

```bash
# Reset package caches
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf .build

# In Xcode
File > Packages > Reset Package Caches
File > Packages > Update to Latest Package Versions

# Command line
xcodebuild -resolvePackageDependencies -project VoiceInk.xcodeproj -scheme VoiceInk
```

## Dependency Locations

### Runtime Locations

After building, frameworks are located at:

```
VoiceInk.app/Contents/Frameworks/
├── whisper.xcframework          # Manually built
├── MediaRemoteAdapter.framework # SPM, embedded
└── (Other SPM frameworks)       # Linked, not embedded
```

### Build-time Locations

During development:

```
~/VoiceInk-Dependencies/
└── whisper.cpp/
    └── build-apple/
        └── whisper.xcframework

~/Library/Developer/Xcode/DerivedData/VoiceInk-*/
├── SourcePackages/           # SPM packages cache
└── Build/Products/Debug/     # Built frameworks
```

## Updating Dependencies

### Update All Swift Packages

```bash
# In Xcode
File > Packages > Update to Latest Package Versions

# Or command line
xcodebuild -resolvePackageDependencies -project VoiceInk.xcodeproj -scheme VoiceInk
```

### Update whisper.cpp

```bash
cd ~/VoiceInk-Dependencies/whisper.cpp
git pull
./build-xcframework.sh
```

## Troubleshooting Dependencies

### Missing Package Errors

If you see errors like "No such module 'FluidAudio'":

1. Verify internet connection (SPM needs to download packages)
2. Reset package caches:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   ```
3. Resolve packages in Xcode: `File > Packages > Resolve Package Versions`

### whisper.xcframework Not Found

```bash
# Check if framework exists
ls -la ~/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework

# If missing, rebuild
make whisper
```

### Version Conflicts

If you encounter version conflicts between packages:

1. Check `VoiceInk.xcodeproj/project.pbxproj` for pinned versions
2. Use Xcode to resolve conflicts: `File > Packages > Resolve Package Versions`
3. Manually specify versions in Xcode package dependencies if needed

## License Information

All dependencies are open source with permissive licenses:

- Most dependencies: MIT License
- Some dependencies: Apache 2.0 or similar permissive licenses
- VoiceInk itself: GPL v3.0

Always review individual dependency licenses before distribution.

## Adding New Dependencies

To add a new Swift Package dependency:

1. In Xcode: `File > Add Package Dependencies`
2. Enter the repository URL
3. Select version requirements
4. Choose target (VoiceInk)
5. Update this DEPENDENCIES.md file

For native frameworks like whisper.xcframework:

1. Build the framework
2. Add to `Frameworks, Libraries, and Embedded Content` in Xcode
3. Update build settings if needed
4. Document in this file
