#!/usr/bin/env python3
"""Select the pinned Zig compiler only after verifying native SDK linking."""

import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def run(args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def discover_sdk():
    environment = dict(os.environ)
    environment.pop("SDKROOT", None)
    return run(
        ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"],
        env=environment, capture_output=True, text=True,
    ).stdout.strip()


def probe(compiler, sdk, required_version):
    try:
        version = run([str(compiler), "version"], capture_output=True, text=True)
        if version.stdout.strip() != required_version:
            return False
        with tempfile.TemporaryDirectory(prefix="ghosttyx-link-probe-") as directory:
            root = Path(directory)
            source = root / "probe.zig"
            source.write_text(
                'extern "c" fn getpid() c_int;\n'
                'pub fn main() void { if (getpid() <= 0) @panic("getpid failed"); }\n'
            )
            executable = root / "probe"
            run(
                [str(compiler), "build-exe", str(source), "-lc", "-OReleaseFast",
                 "--sysroot", str(sdk), "-femit-bin=" + str(executable)],
                capture_output=True, text=True,
            )
            run([str(executable)], capture_output=True, text=True)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def resolve_compiler(sdk, required_version, explicit=None):
    if explicit:
        compiler = Path(shutil.which(explicit) or explicit).resolve()
        if not probe(compiler, sdk, required_version):
            raise RuntimeError(
                "The requested Zig compiler does not match build.zig.zon or cannot "
                "build and run a native libc program with the selected SDK."
            )
        return compiler

    candidate = shutil.which("zig")
    if candidate and probe(Path(candidate), sdk, required_version):
        return Path(candidate).resolve()

    # The versioned Homebrew formula backports Zig's arm64e SDK matching fix.
    # Resolve its keg explicitly instead of requiring a global PATH change.
    brew = shutil.which("brew")
    if brew:
        try:
            result = run([brew, "--prefix", "zig@0.15"], capture_output=True, text=True)
        except subprocess.CalledProcessError:
            result = None
        if result:
            compiler = Path(result.stdout.strip()) / "bin" / "zig"
            if probe(compiler, sdk, required_version):
                return compiler.resolve()
    raise RuntimeError(
        "No SDK-compatible pinned Zig compiler was found. Run brew bundle "
        "in the repository to install the dependencies declared in Brewfile."
    )


def main():
    if sys.argv[1:] == ["--sdk"]:
        print(discover_sdk())
        return
    manifest = Path(__file__).resolve().parent.parent / "build.zig.zon"
    minimum = re.search(r'\.minimum_zig_version\s*=\s*"([^"]+)"', manifest.read_text())
    if not minimum:
        raise RuntimeError("Could not read minimum_zig_version from build.zig.zon.")
    print(resolve_compiler(
        Path(os.environ["SDKROOT"]), minimum.group(1), explicit=os.environ.get("ZIG"),
    ))


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
