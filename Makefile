# Dependencies live in a sibling directory next to this repo checkout.
# Computed relative to the Makefile location so it works on any machine;
# override with `make DEPS_DIR=/custom/path` if your layout differs.
DEPS_DIR ?= $(abspath $(CURDIR)/../voiceink_dependencies)
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
WHISPER_MACOS_SLICE := $(FRAMEWORK_PATH)/macos-arm64_x86_64/whisper.framework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_CODESIGN_IDENTITY ?=
LOCAL_SIGN_IDENTITY ?= $(if $(LOCAL_CODESIGN_IDENTITY),$(LOCAL_CODESIGN_IDENTITY),-)
RUN_APP_NAME ?= VoiceInk
DEBUG_APP_NAME := VoiceInk Dev
INSTALL_PATH := /Applications/VoiceInk.app

# mlx-swift ships a `CudaBuild` prebuild plugin and mlx-swift-lm an
# `MLXHuggingFaceMacros` macro. Xcode refuses to run either unvalidated from the
# command line ("must be enabled before it can be used") and there is no CLI
# equivalent of the GUI trust prompt, so every xcodebuild invocation here has to
# opt out explicitly.
XCB_FLAGS := -skipPackagePluginValidation -skipMacroValidation

.PHONY: all clean whisper setup build local local-stable check check-tcc healthcheck check-env help dev run cli install-cli fix-derived-app release release-setup

# Default target
all: check build

# Development workflow
dev: RUN_APP_NAME = VoiceInk Dev
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@command -v cmake >/dev/null 2>&1 || { echo "cmake is not installed (brew install cmake)"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

# Comprehensive environment check
check-env:
	@if [ -f "./check-build-env.sh" ]; then \
		./check-build-env.sh; \
	else \
		echo "check-build-env.sh not found"; \
		exit 1; \
	fi

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if [ ! -d "$(FRAMEWORK_PATH)" ]; then \
		echo "Building whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		fi; \
		DEPS_DIR="$(DEPS_DIR)" ./build-macos-framework.sh; \
		DEPS_DIR="$(DEPS_DIR)" ./make-framework.sh; \
	else \
		echo "whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi
	@if [ -d "$(WHISPER_MACOS_SLICE)" ]; then \
		if [ -L "$(WHISPER_MACOS_SLICE)/Versions/A/A" ]; then \
			echo "Removing stray self-referencing Versions/A/A symlink..."; \
			rm -f "$(WHISPER_MACOS_SLICE)/Versions/A/A"; \
		fi; \
		echo "Ad-hoc signing whisper.framework (macos-arm64_x86_64)..."; \
		codesign --force --sign - "$(WHISPER_MACOS_SLICE)/Versions/A/whisper" >/dev/null; \
		codesign --force --sign - "$(WHISPER_MACOS_SLICE)" >/dev/null; \
	else \
		echo "Warning: macos slice not found at $(WHISPER_MACOS_SLICE)"; \
	fi

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	./scripts/arch-xcodebuild.sh -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug $(XCB_FLAGS) CODE_SIGN_IDENTITY="" build
	@$(MAKE) --no-print-directory fix-derived-app

# Add missing libwhisper.1.dylib symlink to the Debug build in DerivedData so
# the app can launch (framework binary has install name @rpath/libwhisper.1.dylib).
fix-derived-app:
	@APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -path "*VoiceInk*/Build/Products/Debug/$(DEBUG_APP_NAME).app" -type d -prune 2>/dev/null | head -1); \
	if [ -n "$$APP_PATH" ] && [ -d "$$APP_PATH/Contents/Frameworks/whisper.framework" ]; then \
		echo "Ensuring libwhisper.1.dylib symlink in $$APP_PATH/Contents/Frameworks..."; \
		ln -sfn whisper.framework/Versions/A/whisper "$$APP_PATH/Contents/Frameworks/libwhisper.1.dylib"; \
	fi

# Build for local use without Apple Developer certificate.
# LOCAL_SIGN_IDENTITY may be overridden (e.g. by `local-stable`) to use a real
# code-signing identity so macOS TCC permissions survive future rebuilds.
local: check setup
	@if [ "$(LOCAL_SIGN_IDENTITY)" = "-" ] && [ -d "$(INSTALL_PATH)" ] && [ -z "$$FORCE_ADHOC" ]; then \
		INSTALLED_AUTH=$$(codesign -dvvv "$(INSTALL_PATH)" 2>&1 | awk -F= '/^Authority=/ {print $$2; exit}'); \
		if [ -n "$$INSTALLED_AUTH" ]; then \
			echo "Refusing to overwrite a stably-signed $(INSTALL_PATH) (Authority=$$INSTALLED_AUTH)"; \
			echo "with an ad-hoc build: macOS would drop every TCC grant and the hotkey would"; \
			echo "silently stop working. See COMMON-ISSUES.md §12b."; \
			echo ""; \
			echo "  make local-stable            keep permissions (what you almost certainly want)"; \
			echo "  make local FORCE_ADHOC=1     proceed anyway and re-grant permissions by hand"; \
			exit 1; \
		fi; \
	fi
	@if [ "$(LOCAL_SIGN_IDENTITY)" = "-" ]; then \
		echo "Building VoiceInk for local use (ad-hoc signing — TCC permissions reset on each rebuild)..."; \
	else \
		echo "Building VoiceInk for local use (signing identity: $(LOCAL_SIGN_IDENTITY) — TCC permissions stable across rebuilds)..."; \
	fi
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	./scripts/arch-xcodebuild.sh -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Release \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		$(XCB_FLAGS) \
		CODE_SIGN_IDENTITY="$(LOCAL_SIGN_IDENTITY)" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Release/VoiceInk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		if pgrep -x VoiceInk >/dev/null; then \
			echo "Quitting running VoiceInk before install..."; \
			osascript -e 'tell application "VoiceInk" to quit' 2>/dev/null || true; \
			sleep 1; \
			pkill -9 -x VoiceInk 2>/dev/null || true; \
		fi; \
		echo "Installing VoiceInk.app to $(INSTALL_PATH)..."; \
		rm -rf "$(INSTALL_PATH)"; \
		ditto "$$APP_PATH" "$(INSTALL_PATH)"; \
		xattr -cr "$(INSTALL_PATH)"; \
		FRAMEWORKS_DIR="$(INSTALL_PATH)/Contents/Frameworks"; \
		if [ -d "$$FRAMEWORKS_DIR/whisper.framework" ]; then \
			echo "Adding libwhisper.1.dylib symlink inside app bundle..."; \
			ln -sfn whisper.framework/Versions/A/whisper "$$FRAMEWORKS_DIR/libwhisper.1.dylib"; \
		fi; \
		if [ "$(LOCAL_SIGN_IDENTITY)" != "-" ]; then \
			echo "Re-signing with $(LOCAL_SIGN_IDENTITY) so TCC permissions persist..."; \
			ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements"; \
			SIGN_FLAGS="--force --sign $(LOCAL_SIGN_IDENTITY) --timestamp=none"; \
			find "$(INSTALL_PATH)/Contents/MacOS" -maxdepth 1 -type f -name "*.dylib" | while read mach; do \
				codesign $$SIGN_FLAGS "$$mach" >/dev/null 2>&1 || true; \
			done; \
			codesign $$SIGN_FLAGS --deep --entitlements "$$ENTITLEMENTS" "$(INSTALL_PATH)" >/dev/null; \
		fi; \
		echo ""; \
		echo "Build complete! App installed to: $(INSTALL_PATH)"; \
		echo "Run with: open $(INSTALL_PATH)"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built VoiceInk.app at $$APP_PATH"; \
		exit 1; \
	fi

# Build with a stable, dedicated self-signed identity so TCC permissions
# (mic, accessibility, screen recording, input monitoring, apple events)
# survive future rebuilds. The first run creates the certificate; subsequent
# runs reuse it. Override with `LOCAL_SIGN_IDENTITY=<sha1-or-name>` if needed.
LOCAL_SIGN_CERT_NAME := VoiceInk Local Signing

local-stable: check
	@if [ -z "$$LOCAL_SIGN_IDENTITY" ] || [ "$$LOCAL_SIGN_IDENTITY" = "-" ]; then \
		./scripts/create-local-signing-cert.sh; \
		IDENTITY=$$(security find-identity -p codesigning 2>/dev/null | awk -v n="$(LOCAL_SIGN_CERT_NAME)" 'index($$0, n) {print $$2; exit}'); \
		if [ -z "$$IDENTITY" ]; then \
			echo "Failed to locate a usable '$(LOCAL_SIGN_CERT_NAME)' identity in keychain after creation."; \
			exit 1; \
		fi; \
	else \
		IDENTITY="$$LOCAL_SIGN_IDENTITY"; \
	fi; \
	echo "Using signing identity: $$IDENTITY"; \
	$(MAKE) --no-print-directory local LOCAL_SIGN_IDENTITY="$$IDENTITY"

# Answer "is the hotkey dead because macOS stopped recognising this build?"
# tccd logs a requirement mismatch instead of prompting, so nothing surfaces
# in the UI and the app looks perfectly healthy.
check-tcc:
	@BUNDLE_ID=com.prakashjoshipax.VoiceInk; \
	if [ ! -d "$(INSTALL_PATH)" ]; then \
		echo "$(INSTALL_PATH) is not installed."; \
		exit 1; \
	fi; \
	codesign -dvvv "$(INSTALL_PATH)" 2>&1 | grep -E "^Authority=" || echo "Authority: none (ad-hoc signature)"; \
	MISMATCH=$$(/usr/bin/log show --last 15m --predicate 'process == "tccd"' --info 2>/dev/null \
		| grep "Failed to match existing code requirement for subject $$BUNDLE_ID" | tail -3); \
	if [ -n "$$MISMATCH" ]; then \
		echo ""; \
		echo "$$MISMATCH"; \
		echo ""; \
		echo "macOS is rejecting this signature — every permission is pinned to an older"; \
		echo "one, so the hotkey and the microphone are dead. Re-grant them:"; \
		echo ""; \
		echo "  osascript -e 'quit app \"VoiceInk\"'"; \
		echo "  for s in ListenEvent Accessibility Microphone ScreenCapture; do \\"; \
		echo "      tccutil reset \$$s $$BUNDLE_ID; done"; \
		echo "  open -a VoiceInk"; \
		echo ""; \
		echo "Grant what macOS asks for, then quit and reopen the app once more."; \
		exit 1; \
	fi; \
	echo ""; \
	echo "No permission mismatch logged for $$BUNDLE_ID in the last 15 minutes."

# Run application
run:
	@if [ "$(RUN_APP_NAME)" = "VoiceInk" ] && [ -d "$(INSTALL_PATH)" ]; then \
		echo "Opening $(INSTALL_PATH)..."; \
		open "$(INSTALL_PATH)"; \
	else \
		echo "Looking for $(RUN_APP_NAME).app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "$(RUN_APP_NAME).app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "$(RUN_APP_NAME).app not found. Build it with 'make local' or use 'make dev' for the development app."; \
			exit 1; \
		fi; \
	fi

# Build a signed, notarized DMG and matching local Sparkle Appcast.
release: whisper
	@if [ -n "$(NOTES)" ]; then \
		./scripts/release.sh --notes "$(NOTES)" $(RELEASE_ARGS); \
	else \
		./scripts/release.sh $(RELEASE_ARGS); \
	fi

# Store Apple's notarization credentials securely in Keychain.
release-setup:
	@./scripts/setup-release-notarization.sh

# CLI tool for dictionary export/import
cli:
	swiftc -O -o VoiceInkCLI/voiceink VoiceInkCLI/voiceink.swift -lsqlite3

install-cli: cli
	install -m 755 VoiceInkCLI/voiceink /usr/local/bin/voiceink
	@echo "Installed to /usr/local/bin/voiceink"

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Quick check if required CLI tools are installed"
	@echo "  check-env          Comprehensive build environment check (recommended)"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Prepare whisper framework for linking"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (ad-hoc — TCC perms reset on rebuild)"
	@echo "  local-stable       Build with a stable codesign identity (TCC perms persist)"
	@echo "    LOCAL_SIGN_IDENTITY=<SHA or name> overrides signing identity"
	@echo "  check-tcc          Check whether macOS still recognises the installed build"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  release            Build DMG and Appcast using release-notes/<version>.html"
	@echo "  release-setup      Store notarization credentials in Keychain"
	@echo "  all                Run full build process (default)"
	@echo "  cli                Build the voiceink CLI tool"
	@echo "  install-cli        Build and install CLI to /usr/local/bin/voiceink"
	@echo "  clean              Remove build artifacts and dependencies"
	@echo "  help               Show this help message"
