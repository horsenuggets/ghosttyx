import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "macos_toolchain", Path(__file__).with_name("macos-toolchain.py")
)
TOOLCHAIN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TOOLCHAIN)
VERSION = "0.15.2"


class ToolchainTests(unittest.TestCase):
    def test_sdk_discovery_uses_active_toolchain_without_inherited_override(self):
        def execute(args, **kwargs):
            self.assertEqual(args, ["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"])
            self.assertNotIn("SDKROOT", kwargs["env"])
            self.assertEqual(kwargs["env"]["DEVELOPER_DIR"], "/selected-xcode")
            return subprocess.CompletedProcess(args, 0, "/selected-sdk\n")
        with patch.dict(os.environ,
                        {"SDKROOT": "/unrelated-sdk", "DEVELOPER_DIR": "/selected-xcode"}):
            with patch.object(TOOLCHAIN, "run", side_effect=execute):
                self.assertEqual(TOOLCHAIN.discover_sdk(), "/selected-sdk")
                self.assertEqual(os.environ["SDKROOT"], "/unrelated-sdk")

    def test_probe_checks_version_compile_and_execution(self):
        for version_ok in (False, True):
            for compile_ok in (False, True):
                for execution_ok in (False, True):
                    def execute(args, **kwargs):
                        if args[-1] == "version":
                            version = VERSION if version_ok else "wrong"
                            return subprocess.CompletedProcess(args, 0, version + "\n")
                        if "build-exe" in args and not compile_ok:
                            raise subprocess.CalledProcessError(1, args)
                        if "build-exe" not in args and not execution_ok:
                            raise subprocess.CalledProcessError(1, args)
                        return subprocess.CompletedProcess(args, 0)
                    with self.subTest(version_ok=version_ok, compile_ok=compile_ok,
                                      execution_ok=execution_ok):
                        with patch.object(TOOLCHAIN, "run", side_effect=execute):
                            self.assertEqual(
                                TOOLCHAIN.probe(Path("/compiler"), Path("/sdk"), VERSION),
                                version_ok and compile_ok and execution_ok,
                            )

    def test_missing_compiler_is_not_compatible(self):
        with patch.object(TOOLCHAIN, "run", side_effect=FileNotFoundError):
            self.assertFalse(TOOLCHAIN.probe(Path("/missing"), Path("/sdk"), VERSION))

    def test_explicit_incompatible_compiler_is_rejected(self):
        with patch.object(TOOLCHAIN.shutil, "which", return_value=None):
            with patch.object(TOOLCHAIN, "probe", return_value=False):
                with self.assertRaisesRegex(RuntimeError, "requested Zig"):
                    TOOLCHAIN.resolve_compiler(Path("/sdk"), VERSION, explicit="/bad")

    def test_explicit_compatible_compiler_is_used(self):
        with patch.object(TOOLCHAIN.shutil, "which", return_value=None):
            with patch.object(TOOLCHAIN, "probe", return_value=True):
                self.assertEqual(
                    TOOLCHAIN.resolve_compiler(Path("/sdk"), VERSION, explicit="/compiler"),
                    Path("/compiler"),
                )

    def test_compatible_path_compiler_needs_no_package_lookup(self):
        with patch.object(TOOLCHAIN.shutil, "which", return_value="/compiler"):
            with patch.object(TOOLCHAIN, "probe", return_value=True):
                self.assertEqual(TOOLCHAIN.resolve_compiler(Path("/sdk"), VERSION),
                                 Path("/compiler"))

    def test_packaged_compiler_selected_when_path_compiler_cannot_link(self):
        def find(name):
            return {"zig": "/stock/zig", "brew": "/brew"}.get(name)
        def compatible(compiler, sdk, version):
            return compiler == Path("/package/bin/zig")
        with patch.object(TOOLCHAIN.shutil, "which", side_effect=find), \
             patch.object(TOOLCHAIN, "probe", side_effect=compatible), \
             patch.object(TOOLCHAIN, "run", return_value=subprocess.CompletedProcess(
                 ["brew"], 0, "/package\n")):
            self.assertEqual(TOOLCHAIN.resolve_compiler(Path("/sdk"), VERSION),
                             Path("/package/bin/zig"))

    def test_no_compatible_compiler_reports_declared_dependencies(self):
        with patch.object(TOOLCHAIN.shutil, "which", return_value=None):
            with self.assertRaisesRegex(RuntimeError, "brew bundle"):
                TOOLCHAIN.resolve_compiler(Path("/sdk"), VERSION)

    def test_failed_package_lookup_reports_installation_instructions(self):
        with patch.object(TOOLCHAIN.shutil, "which", return_value="/brew"), \
             patch.object(TOOLCHAIN, "probe", return_value=False), \
             patch.object(TOOLCHAIN, "run", side_effect=subprocess.CalledProcessError(1, ["brew"])):
            with self.assertRaisesRegex(RuntimeError, "brew bundle"):
                TOOLCHAIN.resolve_compiler(Path("/sdk"), VERSION)

    def test_incompatible_package_is_not_used(self):
        with patch.object(TOOLCHAIN.shutil, "which", return_value="/brew"), \
             patch.object(TOOLCHAIN, "probe", return_value=False), \
             patch.object(TOOLCHAIN, "run", return_value=subprocess.CompletedProcess(
                 ["brew"], 0, "/package\n")):
            with self.assertRaisesRegex(RuntimeError, "SDK-compatible"):
                TOOLCHAIN.resolve_compiler(Path("/sdk"), VERSION)

    def test_build_failure_prevents_signing_and_installation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            compiler = root / "zig"
            compiler.write_text("#!/bin/sh\nexit 7\n")
            compiler.chmod(0o755)
            helper = root / "python3"
            helper.write_text(
                '#!/bin/sh\nif [ "$2" = "--sdk" ]; then\n'
                '    printf "%s\\n" /sdk\nelse\n'
                '    printf "%s\\n" "$TEST_COMPILER"\nfi\n'
            )
            helper.chmod(0o755)
            destination = root / "destination"
            application = destination / "GhosttyX.app"
            application.mkdir(parents=True)
            sentinel = application / "untouched"
            sentinel.write_text("existing installation")
            environment = dict(os.environ)
            environment.update({
                "APP_DEST": str(destination),
                "GHOSTTYX_CODESIGN_IDENTITY": "-",
                "PATH": str(root) + os.pathsep + os.environ["PATH"],
                "TEST_COMPILER": str(compiler),
            })
            result = subprocess.run(
                ["/bin/bash", str(Path(__file__).with_name("build-macos.sh"))],
                env=environment, capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 7, result.stderr)
            self.assertEqual(sentinel.read_text(), "existing installation")
            self.assertNotIn("Signing with", result.stdout)
            self.assertNotIn("Installing to", result.stdout)


if __name__ == "__main__":
    unittest.main()
