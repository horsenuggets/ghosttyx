#!/usr/bin/env bash
#
# build-macos.sh
#
# Build and install the GhosttyX macOS app on a machine whose system toolchain
# fights the pinned Zig. It automates two workarounds that are otherwise tribal
# knowledge:
#
#   1. GhosttyX pins a specific Zig version (see `minimum_zig_version` in
#      build.zig.zon). A newer Zig (e.g. from Homebrew) cannot build it. This
#      script uses a matching `zig` if one is already on PATH, otherwise it
#      downloads the pinned Zig into a cache directory and uses that. Nothing
#      system-wide is changed.
#
#   2. The pinned Zig's self-hosted Mach-O linker cannot parse the
#      `libSystem.tbd` shipped in the newest macOS SDK, so linking fails with a
#      wall of "undefined symbol: _sigaction" style errors -- including for
#      Zig's own build runner, which is why `--sysroot` / `SDKROOT` alone are
#      not enough (they do not reach the build-runner compile). The script
#      temporarily makes an older, linkable SDK the default (moves the newest
#      SDK aside and repoints the `MacOSX*.sdk` symlinks), builds, then restores
#      the original SDK layout on exit no matter how the build ends.
#
# Usage:
#     ./scripts/build-macos.sh                        # build + install to /Applications
#     APP_DEST="$HOME/Applications" ./scripts/build-macos.sh
#     ZIG=/path/to/zig ./scripts/build-macos.sh       # use a specific zig binary
#     GHOSTTYX_FALLBACK_SDK=MacOSX15.sdk ./scripts/build-macos.sh
#
# Requirements: macOS, full Xcode reachable through the /usr/local/bin
# {xcodebuild,metal,metallib} wrappers (see AGENTS.md "Fork Notes"), curl, and
# sudo (used only for the temporary SDK swap).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DEST="${APP_DEST:-/Applications}"
APP_NAME="GhosttyX.app"

# --- Resolve the pinned Zig ---------------------------------------------------

ZIG_VERSION="$(sed -n 's/.*\.minimum_zig_version *= *"\([^"]*\)".*/\1/p' \
    "$REPO_DIR/build.zig.zon")"
if [[ -z "$ZIG_VERSION" ]]; then
    echo "Could not read minimum_zig_version from build.zig.zon." >&2
    exit 1
fi

case "$(uname -m)" in
    arm64) ZIG_ARCH="aarch64" ;;
    x86_64) ZIG_ARCH="x86_64" ;;
    *) echo "Unsupported architecture \"$(uname -m)\"." >&2; exit 1 ;;
esac

zig_matches() {
    [[ -x "$1" ]] && [[ "$("$1" version 2>/dev/null)" == "$ZIG_VERSION" ]]
}

if [[ -n "${ZIG:-}" ]] && zig_matches "$ZIG"; then
    ZIG_BIN="$ZIG"
elif command -v zig >/dev/null 2>&1 && zig_matches "$(command -v zig)"; then
    ZIG_BIN="$(command -v zig)"
else
    CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ghosttyx/zig"
    ZIG_BIN="$CACHE_DIR/zig-$ZIG_ARCH-macos-$ZIG_VERSION/zig"
    if ! zig_matches "$ZIG_BIN"; then
        echo "Fetching Zig $ZIG_VERSION for $ZIG_ARCH..."
        mkdir -p "$CACHE_DIR"
        tarball="zig-$ZIG_ARCH-macos-$ZIG_VERSION.tar.xz"
        curl -fSL --retry 5 --retry-delay 2 \
            -o "$CACHE_DIR/$tarball" \
            "https://ziglang.org/download/$ZIG_VERSION/$tarball"
        tar -xf "$CACHE_DIR/$tarball" -C "$CACHE_DIR"
        rm -f "$CACHE_DIR/$tarball"
    fi
fi

if ! zig_matches "$ZIG_BIN"; then
    echo "Could not obtain Zig $ZIG_VERSION." >&2
    exit 1
fi
echo "Using Zig $ZIG_VERSION at \"$ZIG_BIN\"."

# --- Temporarily swap in a linkable macOS SDK --------------------------------

SDK_ROOT="$(xcode-select -p)/SDKs"

# xcrun often reports the MacOSX.sdk symlink rather than the real SDK
# directory, so follow the symlink chain to get the real directory name, and
# take the major version from --show-sdk-version (more reliable than the name).
sdk_path="$(xcrun --show-sdk-path)"
while [[ -L "$sdk_path" ]]; do
    target="$(readlink "$sdk_path")"
    if [[ "$target" == /* ]]; then
        sdk_path="$target"
    else
        sdk_path="$(dirname "$sdk_path")/$target"
    fi
done
NEWEST_SDK="$(basename "$sdk_path")"
NEWEST_MAJOR="$(xcrun --show-sdk-version 2>/dev/null | cut -d. -f1)"

# Pick a fallback SDK: an explicit override, otherwise the highest real SDK
# directory whose major version is lower than the newest SDK's.
FALLBACK_SDK="${GHOSTTYX_FALLBACK_SDK:-}"
if [[ -z "$FALLBACK_SDK" && -n "$NEWEST_MAJOR" ]]; then
    while IFS= read -r sdk; do
        [[ -L "$SDK_ROOT/$sdk" ]] && continue
        major="$(sed -n 's/^MacOSX\([0-9]*\).*/\1/p' <<<"$sdk")"
        [[ -z "$major" ]] && continue
        if (( major < NEWEST_MAJOR )); then
            FALLBACK_SDK="$sdk"
        fi
    done < <(cd "$SDK_ROOT" && ls -d MacOSX*.sdk 2>/dev/null | sort -V)
fi

SWAP_DONE=0
ORIG_DEFAULT="$(readlink "$SDK_ROOT/MacOSX.sdk" 2>/dev/null || true)"
ORIG_MAJOR="$(readlink "$SDK_ROOT/MacOSX${NEWEST_MAJOR}.sdk" 2>/dev/null || true)"

restore_sdk() {
    [[ "$SWAP_DONE" == "1" ]] || return 0
    echo "Restoring original SDK layout..."
    sudo mv "$SDK_ROOT/$NEWEST_SDK.ghosttyx-bak" "$SDK_ROOT/$NEWEST_SDK" 2>/dev/null || true
    [[ -n "$ORIG_DEFAULT" ]] && sudo ln -sfn "$ORIG_DEFAULT" "$SDK_ROOT/MacOSX.sdk"
    [[ -n "$ORIG_MAJOR" ]] && sudo ln -sfn "$ORIG_MAJOR" "$SDK_ROOT/MacOSX${NEWEST_MAJOR}.sdk"
    rm -rf "$(getconf DARWIN_USER_CACHE_DIR)com.apple.DeveloperTools" 2>/dev/null || true
}
trap restore_sdk EXIT

if [[ -n "$FALLBACK_SDK" && "$FALLBACK_SDK" != "$NEWEST_SDK" \
    && -d "$SDK_ROOT/$NEWEST_SDK" && ! -L "$SDK_ROOT/$NEWEST_SDK" ]]; then
    echo "Swapping default SDK for the build: $NEWEST_SDK -> $FALLBACK_SDK"
    SWAP_DONE=1
    sudo mv "$SDK_ROOT/$NEWEST_SDK" "$SDK_ROOT/$NEWEST_SDK.ghosttyx-bak"
    sudo ln -sfn "$FALLBACK_SDK" "$SDK_ROOT/MacOSX.sdk"
    sudo ln -sfn "$FALLBACK_SDK" "$SDK_ROOT/MacOSX${NEWEST_MAJOR}.sdk"
    rm -rf "$(getconf DARWIN_USER_CACHE_DIR)com.apple.DeveloperTools" 2>/dev/null || true
else
    echo "No older SDK swap needed (building against $NEWEST_SDK)."
fi

# --- Build and install -------------------------------------------------------

cd "$REPO_DIR"
echo "Building (this compiles the core, the xcframework, and the Xcode app)..."
"$ZIG_BIN" build -Dxcframework-target=native -Doptimize=ReleaseFast

BUILT_APP="$REPO_DIR/zig-out/$APP_NAME"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Build finished but \"$BUILT_APP\" was not produced." >&2
    exit 1
fi

echo "Installing to \"$APP_DEST/$APP_NAME\"..."
rm -rf "$APP_DEST/$APP_NAME"
ditto "$BUILT_APP" "$APP_DEST/$APP_NAME"

echo
echo "Installed \"$APP_DEST/$APP_NAME\" ($("$BUILT_APP/Contents/MacOS/ghostty" +version 2>/dev/null | head -1))."
