#!/usr/bin/env bash
#
# Build, sign, and install GhosttyX using the active Xcode SDK. The toolchain
# helper probes native linking and can select Homebrew's versioned Zig package,
# which includes the arm64e SDK target-matching fix from Zig PR #31673. No SDK
# files or global developer settings are changed. Run `brew bundle` first.
#
# GHOSTTYX_CODESIGN_IDENTITY must name a keychain signing identity, or "-" for
# explicit ad hoc signing. APP_DEST selects the installation directory. ZIG can
# select an existing compatible compiler; an incompatible override is rejected.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DEST="${APP_DEST:-/Applications}"
APP_NAME="GhosttyX.app"
STAGING_NAME="GhosttyX.staging.app"

# Checked before the long build so a missing identity fails right away.
if [[ -z "${GHOSTTYX_CODESIGN_IDENTITY:-}" ]]; then
    echo "GHOSTTYX_CODESIGN_IDENTITY is not set. Set it to a code signing identity" >&2
    echo "from \"security find-identity -v -p codesigning\", or to \"-\" to sign ad hoc." >&2
    exit 1
fi
if [[ "$GHOSTTYX_CODESIGN_IDENTITY" != "-" ]] \
    && ! security find-identity -v -p codesigning | grep -qF "$GHOSTTYX_CODESIGN_IDENTITY"; then
    echo "The signing identity \"$GHOSTTYX_CODESIGN_IDENTITY\" was not found in the keychain." >&2
    exit 1
fi

# An inherited SDKROOT can point at unrelated Command Line Tools, even when
# xcode-select selects a full Xcode. Keep the compiler and SDK from one toolchain.
SDKROOT="$(env -u SDKROOT python3 "$SCRIPT_DIR/macos-toolchain.py" --sdk)"
export SDKROOT
ZIG_BIN="$(python3 "$SCRIPT_DIR/macos-toolchain.py")"
echo "Using Zig at \"$ZIG_BIN\" with SDK \"$SDKROOT\"."

cd "$REPO_DIR"
echo "Building the core, xcframework, and macOS app."
"$ZIG_BIN" build -Dxcframework-target=native -Doptimize=ReleaseFast

BUILT_APP="$REPO_DIR/zig-out/$STAGING_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Build finished but \"$BUILT_APP\" was not produced." >&2
    exit 1
fi

if [[ "$GHOSTTYX_CODESIGN_IDENTITY" == "-" ]]; then
    echo "Keeping the ad hoc signature."
else
    echo "Signing with \"$GHOSTTYX_CODESIGN_IDENTITY\"..."

    # Nested code has to be signed before whatever contains it, so collect every
    # bundle and Mach-O file inside the app and sign the deepest paths first.
    # Each one keeps its own entitlements and flags, such as the hardened
    # runtime.
    nested_code=()
    while IFS= read -r path; do
        nested_code+=("$path")
    done < <(
        {
            find "$BUILT_APP/Contents" -type d \( -name '*.app' -o -name '*.appex' \
                -o -name '*.bundle' -o -name '*.framework' -o -name '*.plugin' \
                -o -name '*.xpc' \)
            find "$BUILT_APP/Contents" -type f -perm -u+x \
                -exec sh -c 'file -b "$1" | grep -q "Mach-O"' _ {} \; -print
        } | awk -F/ '{ print NF "\t" $0 }' | sort -rn | cut -f2-
    )

    for path in "${nested_code[@]}" "$BUILT_APP"; do
        codesign --force --sign "$GHOSTTYX_CODESIGN_IDENTITY" --timestamp=none \
            --preserve-metadata=entitlements,flags "$path"
    done

    codesign --verify --deep --strict "$BUILT_APP"
fi

echo "Installing to \"$APP_DEST/$APP_NAME\"..."
rm -rf "${APP_DEST:?}/${APP_NAME:?}"
ditto "$BUILT_APP" "$APP_DEST/$APP_NAME"

echo
echo "Installed \"$APP_DEST/$APP_NAME\" ($("$BUILT_APP/Contents/MacOS/ghostty" +version 2>/dev/null | head -1))."
