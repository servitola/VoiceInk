# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
WHISPER_MACOS_SLICE := $(FRAMEWORK_PATH)/macos-arm64_x86_64/whisper.framework
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
INSTALL_PATH := /Applications/VoiceInk.app

.PHONY: all clean whisper setup build local check healthcheck check-env help dev run cli install-cli fix-derived-app

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
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
		else \
			(cd $(WHISPER_CPP_DIR) && git pull); \
		fi; \
		cd $(WHISPER_CPP_DIR) && ./build-xcframework.sh 2>/dev/null || echo "Build completed with warnings"; \
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
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build
	@$(MAKE) --no-print-directory fix-derived-app

# Add missing libwhisper.1.dylib symlink to the Debug build in DerivedData so
# the app can launch (framework binary has install name @rpath/libwhisper.1.dylib).
fix-derived-app:
	@APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -path "*VoiceInk*/Build/Products/Debug/VoiceInk.app" -type d -prune 2>/dev/null | head -1); \
	if [ -n "$$APP_PATH" ] && [ -d "$$APP_PATH/Contents/Frameworks/whisper.framework" ]; then \
		echo "Ensuring libwhisper.1.dylib symlink in $$APP_PATH/Contents/Frameworks..."; \
		ln -sfn whisper.framework/Versions/A/whisper "$$APP_PATH/Contents/Frameworks/libwhisper.1.dylib"; \
	fi

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building VoiceInk for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/VoiceInk/VoiceInk.local.entitlements \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/Debug/VoiceInk.app" && \
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

# Run application
run:
	@if [ -d "$(INSTALL_PATH)" ]; then \
		echo "Opening $(INSTALL_PATH)..."; \
		open "$(INSTALL_PATH)"; \
	else \
		echo "Looking for VoiceInk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "VoiceInk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "VoiceInk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

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
	@echo "  local              Build for local use (no Apple Developer certificate needed)"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  cli                Build the voiceink CLI tool"
	@echo "  install-cli        Build and install CLI to /usr/local/bin/voiceink"
	@echo "  clean              Remove build artifacts and dependencies"
	@echo "  help               Show this help message"