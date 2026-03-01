#!/bin/bash
set -e

DEPS_DIR="${HOME}/VoiceInk-Dependencies"
WHISPER_CPP_DIR="${DEPS_DIR}/whisper.cpp"

cd "${WHISPER_CPP_DIR}"

# Create framework structure
mkdir -p build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/{Headers,Modules,Resources}

# Build dynamic library from static lib
echo "Creating dynamic library..."
clang++ -dynamiclib \
    -arch arm64 -arch x86_64 \
    -mmacosx-version-min=13.3 \
    -Wl,-force_load,build-macos/src/libwhisper.a \
    -Wl,-force_load,build-macos/ggml/src/libggml.a \
    -Wl,-force_load,build-macos/ggml/src/libggml-base.a \
    -Wl,-force_load,build-macos/ggml/src/libggml-cpu.a \
    -Wl,-force_load,build-macos/ggml/src/ggml-metal/libggml-metal.a \
    -Wl,-force_load,build-macos/ggml/src/ggml-blas/libggml-blas.a \
    -framework Accelerate -framework Metal -framework Foundation \
    -install_name "@rpath/whisper.framework/whisper" \
    -o build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/whisper

# Copy headers
echo "Copying headers..."
cp include/whisper.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/
cp ggml/include/ggml.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/ 2>/dev/null || true
cp ggml/include/ggml-alloc.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/ 2>/dev/null || true
cp ggml/include/ggml-backend.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/ 2>/dev/null || true
cp ggml/include/ggml-metal.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/ 2>/dev/null || true
cp ggml/include/ggml-cpu.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/ 2>/dev/null || true
cp ggml/include/ggml-blas.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/ 2>/dev/null || true
cp ggml/include/gguf.h build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Headers/ 2>/dev/null || true

# Create modulemap
cat > build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/Modules/module.modulemap << 'EOF'
framework module whisper {
    header "whisper.h"
    header "ggml.h"
    header "ggml-alloc.h"
    header "ggml-backend.h"
    header "ggml-metal.h"
    header "ggml-cpu.h"
    header "ggml-blas.h"
    header "gguf.h"

    link "c++"
    link framework "Accelerate"
    link framework "Metal"
    link framework "Foundation"

    export *
}
EOF

# Create symlinks
cd build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework
ln -sf Versions/A/whisper whisper
ln -sf Versions/A/Headers Headers
cd Versions
ln -sf A Current

# Create Info.plist
cat > A/Resources/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>whisper</string>
    <key>CFBundleIdentifier</key>
    <string>com.ggerganov.whisper</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>whisper</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
</dict>
</plist>
EOF

cd ../../../../
# Create XCFramework Info.plist
cat > Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AvailableLibraries</key>
    <array>
        <dict>
            <key>LibraryIdentifier</key>
            <string>macos-arm64_x86_64</string>
            <key>LibraryPath</key>
            <string>whisper.framework</string>
            <key>SupportedArchitectures</key>
            <array>
                <string>arm64</string>
                <string>x86_64</string>
            </array>
            <key>SupportedPlatform</key>
            <string>macos</string>
        </dict>
    </array>
    <key>CFBundlePackageType</key>
    <string>XFWK</string>
    <key>XCFrameworkFormatVersion</key>
    <string>1.0</string>
</dict>
</plist>
EOF

echo "Framework created at: ${WHISPER_CPP_DIR}/build-apple/whisper.xcframework"
