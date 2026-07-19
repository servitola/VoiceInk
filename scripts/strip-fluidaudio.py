#!/usr/bin/env python3
"""Remove the FluidAudio SwiftPM package from the Xcode project in place.

FluidAudio / Parakeet depend on the Apple Neural Engine and the Float16 type,
neither of which is available on Intel (x86_64) Macs — the package fails to
compile there. All FluidAudio *usage* in the Swift sources is already guarded
behind `#if canImport(FluidAudio)`, so once the package is unlinked those code
paths fall back to Intel stubs automatically.

This script is invoked by scripts/arch-xcodebuild.sh only on Intel hosts, which
backs the files up first and restores them after the build. It is idempotent:
running it when FluidAudio is already absent is a no-op.
"""
import re
import sys

REPO_FILES = {
    "pbxproj": "VoiceInk.xcodeproj/project.pbxproj",
    "resolved": "VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
}

# The three FluidAudio object identifiers in project.pbxproj:
#   E1DD20DC… XCRemoteSwiftPackageReference "FluidAudio"
#   E1DD20DD… FluidAudio product dependency
#   E1DD20DE… FluidAudio in Frameworks build file
PBX_UUIDS = [
    "E1DD20DC2FA20AD90020AF3B",
    "E1DD20DD2FA20AD90020AF3B",
    "E1DD20DE2FA20AD90020AF3B",
]


def strip_pbxproj(path: str) -> None:
    with open(path, "r") as f:
        lines = f.readlines()

    uuid_alt = "|".join(PBX_UUIDS)
    # Opening line of a multi-line object definition, e.g. "\t\tE1DD20DC… = {"
    block_start = re.compile(r"^\t\t(?:%s)\b.*= \{\s*$" % uuid_alt)

    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if block_start.match(line):
            # Consume the whole brace-balanced object definition.
            depth = line.count("{") - line.count("}")
            i += 1
            while i < n and depth > 0:
                depth += lines[i].count("{") - lines[i].count("}")
                i += 1
            continue
        if any(uuid in line for uuid in PBX_UUIDS):
            # Single-line entry (build-file def or an array reference) — drop it.
            i += 1
            continue
        out.append(line)
        i += 1

    with open(path, "w") as f:
        f.writelines(out)


def strip_resolved(path: str) -> None:
    """Remove the fluidaudio pin object, preserving the file's exact formatting."""
    try:
        with open(path, "r") as f:
            lines = f.readlines()
    except FileNotFoundError:
        return

    out = []
    i = 0
    n = len(lines)
    # A pin object opens with a line that is exactly four spaces + "{" — this
    # distinguishes it from the file's root "{" (column 0) and from inline
    # "state" : { openers.
    pin_start = re.compile(r"^    \{\s*$")
    while i < n:
        if pin_start.match(lines[i]):
            # Look ahead to the matching "}," / "}" to inspect the object body.
            depth = 1
            j = i + 1
            while j < n and depth > 0:
                depth += lines[j].count("{") - lines[j].count("}")
                j += 1
            block = lines[i:j]
            if any('"identity" : "fluidaudio"' in b for b in block):
                i = j  # skip the whole fluidaudio object (and its trailing comma line)
                continue
        out.append(lines[i])
        i += 1

    with open(path, "w") as f:
        f.writelines(out)


def main() -> int:
    strip_pbxproj(REPO_FILES["pbxproj"])
    strip_resolved(REPO_FILES["resolved"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
