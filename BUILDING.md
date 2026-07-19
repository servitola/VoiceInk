# Building VoiceInk

VoiceInk is a macOS-only application. These instructions build it from source
on Apple Silicon or Intel Macs.

## Requirements

- macOS 14.4 or later
- Full Xcode installation with Command Line Tools
- Git
- CMake (`brew install cmake`)

Verify the environment with:

```bash
make check
```

## Local Build

```bash
git clone https://github.com/Beingpax/VoiceInk.git
cd VoiceInk
make local-stable
open /Applications/VoiceInk.app
```

`make local-stable` builds Release in `.local-build`, installs
`VoiceInk.app` in `/Applications`, and creates or reuses a dedicated local
signing identity. Stable signing lets macOS retain microphone, Accessibility,
screen-recording, Input Monitoring, and Apple Events permissions across
rebuilds.

Use `make local` instead for an ad-hoc-signed build. Ad-hoc builds may require
macOS permissions again after every rebuild.

Choose an existing signing identity explicitly:

```bash
make local LOCAL_SIGN_IDENTITY="<SHA or name>"
```

Force ad-hoc signing:

```bash
make local LOCAL_SIGN_IDENTITY=-
```

Local builds use `LocalBuild.xcconfig`, `VoiceInk.local.entitlements`, and the
`LOCAL_BUILD` Swift flag. This fork does not include iCloud dictionary sync or
an automatic updater; pull the source and rebuild to update it.

## Dependencies

Swift Package Manager resolves application packages. The Makefile clones and
builds `whisper.xcframework`, the only dependency that needs a separate native
build.

Dependencies live in `../voiceink_dependencies`, next to the repository, rather
than at a machine-specific absolute path. Override the location when needed:

```bash
make DEPS_DIR=/custom/path local-stable
```

The same override is available to the framework scripts through the `DEPS_DIR`
environment variable. See [DEPENDENCIES.md](DEPENDENCIES.md) for package and
framework details.

### Apple Silicon and Intel

The build detects the host architecture automatically. Apple Silicon builds
include FluidAudio and Parakeet. On Intel, `scripts/arch-xcodebuild.sh`
temporarily removes the FluidAudio package, which requires Apple Neural Engine
and `Float16`, and builds with whisper.cpp support only. Project files are
restored when the build exits.

Set `VOICEINK_TARGET_ARCH=x86_64` or `VOICEINK_TARGET_ARCH=arm64` to exercise a
specific build path.

### Whisper Framework

`make whisper` runs `build-macos-framework.sh` and `make-framework.sh` to create
a self-contained framework. Do not substitute whisper.cpp's dynamic
`build-xcframework.sh` output: it depends on separate `libggml` dylibs that the
application does not embed.

Verify a framework before using it:

```bash
otool -L ../voiceink_dependencies/whisper.cpp/build-apple/whisper.xcframework/macos-arm64_x86_64/whisper.framework/whisper
```

A valid framework has no `libggml` entries. `make whisper` skips an existing
`build-apple` directory, so remove stale output before rebuilding:

```bash
rm -rf ../voiceink_dependencies/whisper.cpp/build-apple
make whisper
```

## Other Commands

- `make check` or `make healthcheck` — verify required tools
- `make check-env` — run the detailed environment check
- `make whisper` — prepare `whisper.xcframework`
- `make setup` — prepare the framework for Xcode
- `make build` — build the standard Debug configuration
- `make local` — build and install with ad-hoc signing by default
- `make local-stable` — build and install with a stable local identity
- `make dev` — build and launch `VoiceInk Dev.app`
- `make run` — launch the installed app or a DerivedData build
- `make release` — create a signed, notarized release package
- `make release-setup` — configure release notarization credentials
- `make clean` — remove the dependency directory
- `make help` — list all commands

## Build with Xcode

```bash
make setup
open VoiceInk.xcodeproj
```

Select the `VoiceInk` scheme. Run builds `VoiceInk Dev.app`; Archive uses
Release. `LOCAL_BUILD` applies only through `make local` or
`make local-stable`.

## Troubleshooting

### `whisper.xcframework` not found

Build the framework and verify its expected location:

```bash
make whisper
ls -la ../voiceink_dependencies/whisper.cpp/build-apple/whisper.xcframework
```

### `No such module 'FluidAudio'` or another Swift package error

Resolve packages again:

```bash
xcodebuild -resolvePackageDependencies -project VoiceInk.xcodeproj -scheme VoiceInk
```

On Intel, build through `make build`, `make local`, or `make local-stable` so
the architecture wrapper can exclude FluidAudio.

### Code-signing failure

Use `make local-stable`, select an identity with `LOCAL_SIGN_IDENTITY`, or force
ad-hoc signing with `LOCAL_SIGN_IDENTITY=-`.

### App asks for permissions after rebuilding

Ad-hoc signatures change identity between builds. Rebuild with
`make local-stable` so macOS can retain TCC permissions.

For more diagnostics, run `make check-env` and consult
[COMMON-ISSUES.md](COMMON-ISSUES.md).
