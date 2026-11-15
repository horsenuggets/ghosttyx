# Agent Development Guide

A file for [guiding coding agents](https://agents.md/).

## Commands

- **Build:** `zig build`
  - If you're on macOS and don't need to build the macOS app, use
    `-Demit-macos-app=false` to skip building the app bundle and speed up
    compilation.
  - **Build + install the macOS app:** Run `brew bundle`, then
    `./scripts/build-macos.sh`. This uses the active Xcode SDK and probes the pinned
    Zig compiler for native linking compatibility. Homebrew's `zig@0.15` includes the
    SDK target-matching fix from Zig PR #31673 and is resolved without changing PATH.
    No SDK files or global developer settings are modified. The script signs the app,
    then installs `GhosttyX.app` to `/Applications`. Set `APP_DEST` to stage it elsewhere.
    `GHOSTTYX_CODESIGN_IDENTITY` must name a code signing identity (or be `-`
    for ad hoc), since a stable signature is what keeps macOS privacy
    permissions from resetting after every build.
- **Test (Zig):** `zig build test`
  - Prefer to run targeted tests with `-Dtest-filter` because the full
    test suite is slow to run.
- **Test filter (Zig)**: `zig build test -Dtest-filter=<test name>`
- **Formatting (Zig)**: `zig fmt .`
- **Formatting (Swift)**: `swiftlint lint --strict --fix`
- **Formatting (other)**: `prettier -w .`

## libghostty-vt

- Build: `zig build -Demit-lib-vt`
- Build WASM: `zig build -Demit-lib-vt -Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`
- Test: `zig build test-lib-vt -Dtest-filter=<filter>`
  - Prefer this when the change is in a libghostty-vt file
- All C enums in `include/ghostty/vt/` must have a `_MAX_VALUE = GHOSTTY_ENUM_MAX_VALUE`
  sentinel as the last entry to force int enum sizing (pre-C23 portability).

## Directory Structure

- Shared Zig core: `src/`
- macOS app: `macos/`
- GTK (Linux and FreeBSD) app: `src/apprt/gtk`

## Fork Notes

This is the GhosttyX fork (`horsenuggets/ghosttyx`). It has diverged from
upstream `ghostty-org/ghostty` and is the source of truth for the
GhosttyX.app installed at `/Applications/GhosttyX.app`. Changes ship through a
branch and pull request to this fork's `main`, never through an upstream PR.
