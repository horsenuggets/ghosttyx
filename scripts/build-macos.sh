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
#      not enough (they do not reach the build-runner compile). Zig asks
#      `xcrun --show-sdk-path` which SDK to use, and current Xcodes answer
#      with the real SDK directory rather than the `MacOSX.sdk` symlink, so
#      repointing the symlinks has no effect. The script puts a temporary
#      `xcrun` shim on `PATH` for the build that answers SDK queries with an
#      older, linkable SDK and forwards everything else to the real xcrun. The
#      newest SDK is left untouched, because xcodebuild resolves
#      `SDKROOT = macosx` itself and needs it for the Swift sources. The
#      fallback is taken from the active Xcode or, when Xcode ships only one
#      SDK, from the Command Line Tools.
#
# Usage:
#     ./scripts/build-macos.sh                        # build + install to /Applications
#     APP_DEST="$HOME/Applications" ./scripts/build-macos.sh
#     ZIG=/path/to/zig ./scripts/build-macos.sh       # use a specific zig binary
#     GHOSTTYX_FALLBACK_SDK=MacOSX15.sdk ./scripts/build-macos.sh
#
# Requirements: macOS, full Xcode reachable through the /usr/local/bin
# {xcodebuild,metal,metallib} wrappers (see AGENTS.md "Fork Notes"), and curl.

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

DEVELOPER_DIR="$(xcode-select -p)"
if [ -d "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs" ]; then
    SDK_ROOT="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs"
else
    SDK_ROOT="$DEVELOPER_DIR/SDKs"
fi

# Follow the symlink chain so SDK aliases resolve to a real directory, and read
# the version from the SDK itself rather than trusting the directory name.
resolve_sdk_path() {
    local path="$1" target
    while [[ -L "$path" ]]; do
        target="$(readlink "$path")"
        if [[ "$target" == /* ]]; then
            path="$target"
        else
            path="$(dirname "$path")/$target"
        fi
    done
    printf '%s\n' "$path"
}

sdk_version() {
    local path version
    path="$(resolve_sdk_path "$1")"
    version="$(basename "$path")"
    version="$(sed -n 's/^MacOSX\([0-9][0-9.]*\)\.sdk$/\1/p' <<<"$version")"
    if [[ -z "$version" && -f "$path/SDKSettings.json" ]]; then
        version="$(plutil -extract Version raw -o - "$path/SDKSettings.json" 2>/dev/null || true)"
    fi
    printf '%s\n' "$version"
}

NEWEST_SDK="$(basename "$(resolve_sdk_path "$(xcrun --show-sdk-path)")")"
NEWEST_MAJOR="$(xcrun --show-sdk-version 2>/dev/null | cut -d. -f1)"

# Pick a fallback SDK: an explicit override, otherwise the highest real SDK
# directory whose major version is lower than the newest SDK's. Current Xcodes
# ship only one SDK, so also look in the Command Line Tools, which keep the
# older SDKs. The fallback is kept as an absolute path since it may live
# outside the active SDK root.
CLT_SDK_ROOT="/Library/Developer/CommandLineTools/SDKs"
FALLBACK_SDK="${GHOSTTYX_FALLBACK_SDK:-}"
if [[ -n "$FALLBACK_SDK" && "$FALLBACK_SDK" != /* ]]; then
    # Aliases such as MacOSX15.sdk may live in either root, so look in both.
    for root in "$SDK_ROOT" "$CLT_SDK_ROOT"; do
        if [[ -e "$root/$FALLBACK_SDK" ]]; then
            FALLBACK_SDK="$root/$FALLBACK_SDK"
            break
        fi
    done
    [[ "$FALLBACK_SDK" == /* ]] || FALLBACK_SDK="$SDK_ROOT/$FALLBACK_SDK"
fi
if [[ -z "$FALLBACK_SDK" && -n "$NEWEST_MAJOR" ]]; then
    # Collect every eligible SDK so the newest one wins across all roots,
    # including newer patch releases within the same major version.
    sdk_candidates=()
    for root in "$SDK_ROOT" "$CLT_SDK_ROOT"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r sdk; do
            [[ -L "$root/$sdk" ]] && continue
            version="$(sed -n 's/^MacOSX\([0-9][0-9.]*\)\.sdk$/\1/p' <<<"$sdk")"
            [[ -z "$version" ]] && continue
            if (( ${version%%.*} < NEWEST_MAJOR )); then
                sdk_candidates+=("$version $root/$sdk")
            fi
        done < <(cd "$root" && ls -d MacOSX*.sdk 2>/dev/null)
    done
    if (( ${#sdk_candidates[@]} > 0 )); then
        FALLBACK_SDK="$(printf '%s\n' "${sdk_candidates[@]}" \
            | sort -V | tail -n1 | cut -d' ' -f2-)"
    fi
fi

if [[ -n "$FALLBACK_SDK" ]]; then
    FALLBACK_SDK="$(resolve_sdk_path "$FALLBACK_SDK")"
fi
if [[ -n "${GHOSTTYX_FALLBACK_SDK:-}" && ! -d "$FALLBACK_SDK" ]]; then
    echo "Could not find the requested SDK \"$GHOSTTYX_FALLBACK_SDK\"." >&2
    exit 1
fi

SHIM_DIR=""
cleanup_shim() {
    if [[ -n "$SHIM_DIR" ]]; then
        rm -rf "$SHIM_DIR"
    fi
}
trap cleanup_shim EXIT

if [[ -n "$FALLBACK_SDK" && "$FALLBACK_SDK" != "$SDK_ROOT/$NEWEST_SDK" \
    && -d "$FALLBACK_SDK" ]]; then
    FALLBACK_VERSION="$(sdk_version "$FALLBACK_SDK")"
    echo "Building against $(basename "$FALLBACK_SDK") via an xcrun shim."

    SHIM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ghosttyx-xcrun.XXXXXX")"
    cat > "$SHIM_DIR/xcrun" <<EOF
#!/bin/sh
# Answer Zig's macOS SDK queries with the fallback SDK and forward everything
# else to the real xcrun.
sdk=macosx
previous=""
for arg in "\$@"; do
    if [ "\$previous" = "--sdk" ] || [ "\$previous" = "-sdk" ]; then
        sdk="\$arg"
    fi
    previous="\$arg"
done
[ "\$sdk" = "macosx" ] || exec /usr/bin/xcrun "\$@"
for arg in "\$@"; do
    case "\$arg" in
        --show-sdk-path)
            printf '%s\n' "$FALLBACK_SDK"
            exit 0
            ;;
        --show-sdk-version)
            printf '%s\n' "$FALLBACK_VERSION"
            exit 0
            ;;
    esac
done
exec /usr/bin/xcrun "\$@"
EOF
    chmod +x "$SHIM_DIR/xcrun"
    export PATH="$SHIM_DIR:$PATH"
else
    echo "No older SDK needed (building against $NEWEST_SDK)."
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
