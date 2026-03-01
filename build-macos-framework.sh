#!/bin/bash
set -e

DEPS_DIR="${HOME}/VoiceInk-Dependencies"
WHISPER_CPP_DIR="${DEPS_DIR}/whisper.cpp"

if [ ! -d "${WHISPER_CPP_DIR}" ]; then
    echo "Cloning whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp.git "${WHISPER_CPP_DIR}"
fi

cd "${WHISPER_CPP_DIR}"

# Clean previous builds
rm -rf build-apple build-macos

# Build macOS framework (static library only)
echo "Building macOS framework..."
cmake -B build-macos \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 \
    -DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
    -DWHISPER_COREML="OFF" \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=ON \
    -DGGML_BLAS_DEFAULT=ON \
    .

make -C build-macos -j$(sysctl -n hw.ncpu)

# Create framework structure
mkdir -p build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/{Headers,Modules,Resources}
mkdir -p build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A

# Build the static library for both architectures
echo "Creating static library framework..."
# The cmake build should have created libwhisper.a
if [ -f "build-macos/src/libwhisper.a" ]; then
    cp build-macos/src/libwhisper.a build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/Versions/A/whisper
else
    echo "Error: libwhisper.a not found"
    find build-macos -name "libwhisper.a" -o -name "libwhisper*"
    exit 1
fi

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

# Create symlinks for framework structure
cd build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework
ln -sf Versions/A/whisper whisper
ln -sf Versions/A/Headers Headers
cd Versions
ln -sf A Current
cd ../..

# Create Info.plist
cat > whisper.framework/Versions/A/Resources/Info.plist << 'EOF'
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

echo "Framework created at: ${WHISPER_CPP_DIR}/build-apple/whisper.xcframework"
