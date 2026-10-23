"""The held fixture is opt-in and must never start from an unattended CI run."""
import os
import plistlib
import re
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check-ai-usage-ui.sh"


class UsageUICLIContract(unittest.TestCase):
    def invoke(self, *arguments, ci=None):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            marker = path / "swift-called"
            fake_swift = path / "swift"
            fake_swift.write_text('#!/bin/sh\ntouch "$QA_SWIFT_MARKER"\nexit 93\n')
            fake_swift.chmod(0o755)
            environment = dict(os.environ, PATH=directory + ":" + os.environ["PATH"], QA_SWIFT_MARKER=str(marker))
            for key in ["CI", "GITHUB_ACTIONS", "HAPPY_LULU_SKIP_BUILD", "HAPPY_LULU_MATERIAL_MODE"]:
                environment.pop(key, None)
            if ci:
                environment.update(ci)
            result = subprocess.run(["bash", str(SCRIPT), *arguments], env=environment,
                                    capture_output=True, text=True, timeout=5)
            return result, marker.exists()

    def test_interactive_template_restricts_external_controls_and_fails_closed_on_drift(self):
        # Exercise the exact generated-copy operation against current production input.
        code = SCRIPT.read_text().split("<<'PYFIXTURE'\n", 1)[1].split("\nPYFIXTURE", 1)[0]
        repository = SCRIPT.parent.parent
        for drift in [False, True]:
            with self.subTest(drift=drift), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for relative in ["Sources/AfterSix/PluginManagerModel.swift", "Sources/AIUsageIntegration/AIUsageSettingsView.swift"]:
                    target = root / relative
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_text((repository / relative).read_text())
                output = root / "probe"
                plist = output / "HappyLulu QA Synthetic.app/Contents/Info.plist"
                plist.parent.mkdir(parents=True)
                plist.write_bytes(plistlib.dumps({}))
                if drift:
                    source = root / "Sources/AfterSix/PluginManagerModel.swift"
                    source.write_text(source.read_text().replace('factories["mac-calendar"] =', 'factories["calendar-new"] ='))
                result = subprocess.run([sys.executable, "-c", code, str(output)], cwd=root,
                                        capture_output=True, text=True, timeout=5)
                if drift:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse((output / "PluginManagerModel.swift").exists())
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)
                    manager = (output / "PluginManagerModel.swift").read_text()
                    self.assertIn('catalog.removeAll { !["ai-usage", "cpu-runner"].contains($0.id) }', manager)
                    usage = (output / "AIUsageSettingsView.swift").read_text()
                    self.assertIn('.toggleStyle(.switch).disabled(true)', usage)
                    self.assertEqual((root / "Sources/AfterSix/PluginManagerModel.swift").read_text(),
                                     (repository / "Sources/AfterSix/PluginManagerModel.swift").read_text())

    def test_interactive_panel_size_tracks_production_geometry_and_updates(self):
        repository = SCRIPT.parent.parent
        production = (repository / "Sources/AfterSix/PanelView.swift").read_text()
        probe = (repository / "Tests/AIUsageUIProbe/main.swift").read_text()
        shape = r"width: (\d+), height: CGFloat\((\d+) \+ (\d+) \* plugins\.menuBarItems\.count\)"
        production_geometry = re.search(shape, production)
        self.assertIsNotNone(production_geometry)
        sizing = re.search(r"private var panelSize: NSSize \{(.*?)\n    \}", probe, re.S)
        self.assertIsNotNone(sizing, "The held panel must compute its size from enabled providers")
        fixture_geometry = re.search(shape, sizing.group(1))
        self.assertIsNotNone(fixture_geometry)
        self.assertEqual(fixture_geometry.groups(), production_geometry.groups())
        self.assertIn("plugins.panelProviders.reduce(0) { $0 + $1.panelHeight }", sizing.group(1))
        self.assertIn("+ Self.bannerHeight", sizing.group(1))
        self.assertIn(".frame(height: Self.bannerHeight)", probe)
        self.assertIn("panel?.updateContentSize(panelSize)", probe)
        self.assertIn("MenuBarPanel(content: controller, size: panelSize)", probe)

    def test_automatic_invocation_reaches_compiler_without_empty_optional_sources(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = root / "compiler-called"
            for name, body in {
                "swift": '#!/bin/sh\nprintf "%s\\n" "$QA_BUILD_DIR"\n',
                "swiftc": '#!/bin/sh\ntouch "$QA_COMPILER_MARKER"\nexit 93\n',
                "ditto": '#!/bin/sh\nexit 0\n',
            }.items():
                path = root / name
                path.write_text(body)
                path.chmod(0o755)
            environment = dict(os.environ, PATH=directory + ":" + os.environ["PATH"],
                               QA_BUILD_DIR=directory, QA_COMPILER_MARKER=str(marker), HAPPY_LULU_SKIP_BUILD="1")
            environment.pop("HAPPY_LULU_MATERIAL_MODE", None)
            result = subprocess.run(["/bin/bash", str(SCRIPT)], env=environment,
                                    capture_output=True, text=True, timeout=5)
            self.assertEqual(result.returncode, 93, result.stderr)
            self.assertTrue(marker.exists(), "The automatic path must survive macOS Bash 3.2 nounset handling")

    def test_help_does_not_build(self):
        result, built = self.invoke("--help")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--interactive", result.stdout)
        self.assertFalse(built)

    def test_unknown_flags_fail_before_build(self):
        for arguments in [("--unknown",), ("--interactive", "--unknown"), ("--interactive", "--interactive")]:
            with self.subTest(arguments=arguments):
                result, built = self.invoke(*arguments)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertFalse(built)

    def test_interactive_is_rejected_in_ci_before_build(self):
        for ci in [{"CI": "true"}, {"GITHUB_ACTIONS": "true"}, {"CI": "1"}]:
            with self.subTest(ci=ci):
                result, built = self.invoke("--interactive", ci=ci)
                self.assertEqual(result.returncode, 64, result.stderr)
                self.assertIn("interactive", result.stderr)
                self.assertFalse(built)

    def test_automatic_still_builds_in_ci(self):
        result, built = self.invoke(ci={"CI": "true"})
        self.assertEqual(result.returncode, 93, result.stderr)
        self.assertTrue(built)

    def test_interactive_requires_explicit_flag(self):
        result, built = self.invoke("--interactive")
        self.assertEqual(result.returncode, 93, result.stderr)
        self.assertTrue(built)


if __name__ == "__main__":
    unittest.main()
