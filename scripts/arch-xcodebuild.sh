#!/usr/bin/env bash
#
# Arch-aware xcodebuild wrapper.
#
# VoiceInk's Parakeet engine (the FluidAudio SwiftPM package) depends on the
# Apple Neural Engine and the Float16 type, neither of which exists on Intel
# (x86_64) Macs — the package fails to compile there. All FluidAudio usage in the
# Swift sources is guarded behind `#if canImport(FluidAudio)`, so the app builds
# fine without the package (whisper.cpp engine only).
#
# On an Intel host this wrapper temporarily strips the FluidAudio package from the
# Xcode project, runs xcodebuild, then always restores the project files (even if
# the build fails). On Apple Silicon it builds the project unchanged, so Parakeet
# stays available. The committed project always contains FluidAudio.
#
# Override the detected arch with VOICEINK_TARGET_ARCH=x86_64|arm64 (used by CI or
# to test the Intel path from an Apple Silicon machine).
#
# All arguments are forwarded verbatim to xcodebuild.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PBXPROJ="VoiceInk.xcodeproj/project.pbxproj"
RESOLVED="VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
ARCH="${VOICEINK_TARGET_ARCH:-$(uname -m)}"

restore_project() {
    if [ -f "$PBXPROJ.fa-bak" ]; then mv -f "$PBXPROJ.fa-bak" "$PBXPROJ"; fi
    if [ -f "$RESOLVED.fa-bak" ]; then mv -f "$RESOLVED.fa-bak" "$RESOLVED"; fi
}

if [ "$ARCH" = "x86_64" ]; then
    echo "==> Intel (x86_64) host — building WITHOUT FluidAudio/Parakeet (whisper.cpp engine only)."
    cp "$PBXPROJ" "$PBXPROJ.fa-bak"
    if [ -f "$RESOLVED" ]; then cp "$RESOLVED" "$RESOLVED.fa-bak"; fi
    trap restore_project EXIT
    python3 "$REPO_ROOT/scripts/strip-fluidaudio.py"
else
    echo "==> Apple Silicon ($ARCH) host — building FULL version with FluidAudio/Parakeet."
fi

xcodebuild "$@"
