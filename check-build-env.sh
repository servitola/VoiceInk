#!/bin/bash

# VoiceInk Build Environment Checker
# This script verifies that your system has all the required tools and dependencies
# to build VoiceInk from source.

set -e

echo "=========================================="
echo "VoiceInk Build Environment Checker"
echo "=========================================="
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track if any checks fail
FAILED=0

# Function to print success
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to print failure
print_failure() {
    echo -e "${RED}✗${NC} $1"
    FAILED=1
}

# Function to print warning
print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

echo "Checking system requirements..."
echo ""

# Check macOS version
echo -n "macOS version: "
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_MAJOR=$(echo $MACOS_VERSION | cut -d. -f1)
echo "$MACOS_VERSION"

if [ "$MACOS_MAJOR" -ge 14 ]; then
    print_success "macOS version is 14.0 or later (required: 14.0+)"
else
    print_failure "macOS version must be 14.0 or later (Sonoma or newer)"
fi
echo ""

# Check architecture
echo -n "Architecture: "
ARCH=$(uname -m)
echo "$ARCH"
if [ "$ARCH" = "arm64" ]; then
    print_success "Apple Silicon (M1/M2/M3) detected"
elif [ "$ARCH" = "x86_64" ]; then
    print_success "Intel Mac detected"
else
    print_warning "Unknown architecture: $ARCH"
fi
echo ""

# Check Xcode
echo "Checking Xcode installation..."
if command -v xcodebuild &> /dev/null; then
    XCODE_VERSION=$(xcodebuild -version | head -1)
    echo "$XCODE_VERSION"
    print_success "Xcode is installed"

    # Check Xcode version
    XCODE_VER=$(xcodebuild -version | grep "Xcode" | awk '{print $2}' | cut -d. -f1)
    if [ "$XCODE_VER" -ge 15 ]; then
        print_success "Xcode version is 15.0 or later (required: 15.0+)"
    else
        print_failure "Xcode version must be 15.0 or later (you have: $XCODE_VERSION)"
    fi
else
    print_failure "Xcode is not installed. Install from Mac App Store."
fi
echo ""

# Check Command Line Tools
echo "Checking Xcode Command Line Tools..."
if xcode-select -p &> /dev/null; then
    CLT_PATH=$(xcode-select -p)
    echo "Path: $CLT_PATH"
    print_success "Xcode Command Line Tools are installed"
else
    print_failure "Xcode Command Line Tools not installed. Run: xcode-select --install"
fi
echo ""

# Check Git
echo "Checking Git..."
if command -v git &> /dev/null; then
    GIT_VERSION=$(git --version)
    echo "$GIT_VERSION"
    print_success "Git is installed"
else
    print_failure "Git is not installed. Install Xcode Command Line Tools."
fi
echo ""

# Check Swift
echo "Checking Swift..."
if command -v swift &> /dev/null; then
    SWIFT_VERSION=$(swift --version | head -1)
    echo "$SWIFT_VERSION"
    print_success "Swift is installed"
else
    print_failure "Swift is not installed. Install Xcode."
fi
echo ""

# Check Make
echo "Checking Make..."
if command -v make &> /dev/null; then
    MAKE_VERSION=$(make --version | head -1)
    echo "$MAKE_VERSION"
    print_success "Make is installed"
else
    print_warning "Make is not installed (optional but recommended)"
fi
echo ""

# Check disk space
echo "Checking disk space..."
AVAILABLE_GB=$(df -H . | tail -1 | awk '{print $4}' | sed 's/Gi//')
echo "Available space: ~${AVAILABLE_GB}GB"
# Simple check - if available space looks reasonable
if [ ! -z "$AVAILABLE_GB" ]; then
    print_success "Disk space check passed (need ~5GB for dependencies and build)"
else
    print_warning "Could not determine disk space. Ensure you have at least 5GB free."
fi
echo ""

# Check for whisper.xcframework
echo "Checking for whisper.xcframework..."
WHISPER_PATH="$HOME/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework"
if [ -d "$WHISPER_PATH" ]; then
    print_success "whisper.xcframework found at: $WHISPER_PATH"
else
    print_warning "whisper.xcframework not found. It will be built automatically when you run 'make all'"
    echo "           Expected location: $WHISPER_PATH"
fi
echo ""

# Check internet connectivity (for SPM)
echo "Checking internet connectivity (required for Swift Package Manager)..."
if ping -c 1 github.com &> /dev/null; then
    print_success "Internet connection available"
else
    print_warning "Cannot reach github.com. Internet is required to download Swift packages."
fi
echo ""

# Check Xcode license
echo "Checking Xcode license acceptance..."
if xcodebuild -checkFirstLaunchStatus &> /dev/null; then
    print_success "Xcode license has been accepted"
else
    print_failure "Xcode license needs to be accepted. Run: sudo xcodebuild -license accept"
fi
echo ""

# Check for Rosetta 2 (on Apple Silicon)
if [ "$ARCH" = "arm64" ]; then
    echo "Checking Rosetta 2 (for Intel binary compatibility)..."
    if pgrep -q oahd || [ -f /Library/Apple/usr/libexec/oah/libRosettaRuntime ]; then
        print_success "Rosetta 2 is installed"
    else
        print_warning "Rosetta 2 not detected. May be needed for some build tools."
        echo "           Install with: softwareupdate --install-rosetta --agree-to-license"
    fi
    echo ""
fi

# Check git configuration
echo "Checking Git configuration..."
GIT_USER=$(git config --global user.name 2>/dev/null)
GIT_EMAIL=$(git config --global user.email 2>/dev/null)
if [ -n "$GIT_USER" ] && [ -n "$GIT_EMAIL" ]; then
    print_success "Git is configured (user: $GIT_USER)"
else
    print_warning "Git user not configured. Set with:"
    echo "           git config --global user.name \"Your Name\""
    echo "           git config --global user.email \"your@email.com\""
fi
echo ""

# Check Xcode Command Line Tools location
echo "Checking Xcode Command Line Tools configuration..."
CLT_ACTUAL=$(xcode-select -p 2>/dev/null)
CLT_EXPECTED="/Applications/Xcode.app/Contents/Developer"
if [ "$CLT_ACTUAL" = "$CLT_EXPECTED" ]; then
    print_success "Command Line Tools pointing to Xcode (correct)"
elif [ -n "$CLT_ACTUAL" ]; then
    print_warning "Command Line Tools at: $CLT_ACTUAL"
    echo "           Expected: $CLT_EXPECTED"
    echo "           Reset with: sudo xcode-select --switch $CLT_EXPECTED"
else
    print_failure "Command Line Tools path not set"
fi
echo ""

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo ""
    echo "You can now build VoiceInk with:"
    echo "  make all"
    echo ""
    echo "Or to build and run:"
    echo "  make dev"
else
    echo -e "${RED}Some checks failed.${NC}"
    echo ""
    echo "Please fix the issues above before building."
    echo "See BUILDING.md for detailed instructions."
    exit 1
fi
