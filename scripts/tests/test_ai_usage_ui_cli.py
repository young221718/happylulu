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
    def test_generated_app_model_does_not_use_persistent_countdown_defaults(self):
        repository = SCRIPT.parent.parent
        code = SCRIPT.read_text().split("<<'PY'\n", 1)[1].split('\nPY', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            generated = subprocess.run([sys.executable, '-c', code,
                str(repository / 'Sources/AfterSix/AppearanceModel.swift'),
                str(output / 'AppearanceModel.swift'), str(output / 'Info.plist')], cwd=repository,
                capture_output=True, text=True, timeout=5)
            self.assertEqual(generated.returncode, 0, generated.stderr)
            model = (output / 'AppModel.swift').read_text()
            self.assertTrue('CountdownDisplay.saved(in: ProbePreferences.shared)' in model, 'Countdown load must use fixture preferences')
            self.assertTrue('choice.save(in: ProbePreferences.shared)' in model, 'Countdown save must use fixture preferences')
            self.assertNotIn('CountdownDisplay.saved()', model)
            self.assertNotIn('choice.save()', model)

    def test_cleanup_unregisters_exact_app_before_deletion_and_reports_failure(self):
        body = SCRIPT.read_text().split('cleanup() {\n', 1)[1].split('\n}\ntrap cleanup EXIT', 1)[0]
        for unregister_status, initial_status in [(0, 0), (0, 7), (9, 0)]:
            with self.subTest(unregister_status=unregister_status, initial_status=initial_status), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixture = root / 'fixture'
                app = fixture / 'happylulu-dev.app'
                binary = app / 'Contents/MacOS/UsageProbe'
                binary.parent.mkdir(parents=True)
                binary.write_text('fixture')
                binary.chmod(0o755)
                lock = root / 'fixture.lock'
                lock.mkdir()
                command = root / 'lsregister'
                command.write_text('''#!/bin/sh
test "$1" = -u && test "$2" = "$QA_EXPECTED_APP" && test -f "$2/Contents/MacOS/UsageProbe" || exit 88
printf '%s' "$2" > "$QA_UNREGISTER_CAPTURE"
exit "$QA_UNREGISTER_STATUS"
''')
                command.chmod(0o755)
                capture = root / 'unregistered'
                environment = dict(os.environ, QA_EXPECTED_APP=str(app), QA_UNREGISTER_CAPTURE=str(capture),
                    QA_UNREGISTER_STATUS=str(unregister_status))
                code = 'probe_dir="$1"; app="$2"; lock_dir="$3"; lsregister="$4"\ncleanup() {\n' + body + '\n}\n(exit "$5"); cleanup'
                result = subprocess.run(['bash', '-c', code, 'cleanup-test', str(fixture), str(app), str(lock), str(command), str(initial_status)],
                    env=environment, capture_output=True, text=True, timeout=5)
                self.assertTrue(capture.exists(), 'Cleanup must unregister the exact app while its bundle still exists')
                self.assertEqual(capture.read_text(), str(app))
                if unregister_status:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn('FAIL', result.stderr)
                    self.assertTrue(binary.exists(), 'Keep the bundle for a targeted unregister retry')
                    self.assertTrue(lock.exists())
                else:
                    self.assertEqual(result.returncode, initial_status, result.stderr)
                    self.assertFalse(fixture.exists())
                    self.assertFalse(lock.exists())

    def test_existing_development_fixture_is_not_overwritten_or_run_concurrently(self):
        for occupied in ['happylulu-dev-synthetic.lock', 'happylulu-dev-synthetic']:
            with self.subTest(occupied=occupied), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / occupied
                path.mkdir()
                sentinel = path / 'preserved'
                sentinel.write_text('existing fixture')
                result, built = self.invoke(ci={'TMPDIR': directory})
                self.assertEqual(result.returncode, 73, result.stderr)
                self.assertFalse(built)
                self.assertEqual(sentinel.read_text(), 'existing fixture')

    def test_synthetic_preferences_do_not_write_or_delete_persistent_preferences(self):
        repository = SCRIPT.parent.parent
        helper = repository / 'Tests/AIUsageUIProbe/ProbePreferences.swift'
        self.assertTrue(helper.is_file(), 'The fixed Dev identity needs nonpersistent fixture preferences')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'main.swift'
            source.write_text('''import Foundation
let name = "happylulu-dev.preference-regression." + UUID().uuidString
let real = UserDefaults(suiteName: name)!
real.set("existing", forKey: "sentinel")
defer { real.removePersistentDomain(forName: name) }
let defaults = ProbePreferences(suiteName: name)!
precondition(defaults.object(forKey: "sentinel") == nil)
defaults.set("korean", forKey: "language")
defaults.set(true, forKey: "enabled")
defaults.set(Data([1, 2]), forKey: "data")
CountdownDisplay.seconds.save(in: defaults)
precondition(CountdownDisplay.saved(in: defaults) == .seconds)
precondition(defaults.string(forKey: "language") == "korean")
precondition(defaults.bool(forKey: "enabled"))
precondition(defaults.data(forKey: "data") == Data([1, 2]))
defaults.removeObject(forKey: "language")
precondition(defaults.string(forKey: "language") == nil)
precondition(NSDictionary(dictionary: real.persistentDomain(forName: name)!).isEqual(to: ["sentinel": "existing"]))
print("PASS in-memory fixture preferences preserve the persistent domain")
''')
            compiled = subprocess.run(['swiftc', '-module-cache-path', str(root / 'modules'), str(helper),
                str(repository / 'Sources/AfterSixCore/CountdownDisplay.swift'), str(source), '-o', str(root / 'probe')],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stderr)
            checked = subprocess.run([str(root / 'probe')], capture_output=True, text=True, timeout=10)
            self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_both_modes_use_the_single_development_app_identity(self):
        for arguments in [(), ("--interactive",)]:
            with self.subTest(arguments=arguments), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                capture = root / "identity.plist"
                for name, body in {
                    "swift": '#!/bin/sh\nprintf "%s\\n" "$QA_BUILD_DIR"\n',
                    "swiftc": '''#!/usr/bin/env python3
import os, pathlib, plistlib, sys
binary = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])
info = plistlib.loads((binary.parent.parent / 'Info.plist').read_bytes())
info['QAOutputPath'] = str(binary)
pathlib.Path(os.environ['QA_IDENTITY_CAPTURE']).write_bytes(plistlib.dumps(info))
sys.exit(93)
''',
                    "ditto": '#!/bin/sh\nexit 0\n',
                }.items():
                    path = root / name
                    path.write_text(body)
                    path.chmod(0o755)
                environment = dict(os.environ, PATH=directory + ":" + os.environ["PATH"],
                    QA_BUILD_DIR=directory, QA_IDENTITY_CAPTURE=str(capture), HAPPY_LULU_SKIP_BUILD="1")
                for key in ["CI", "GITHUB_ACTIONS", "HAPPY_LULU_MATERIAL_MODE"]:
                    environment.pop(key, None)
                result = subprocess.run(["/bin/bash", str(SCRIPT), *arguments], env=environment,
                    capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 93, result.stderr)
                info = plistlib.loads(capture.read_bytes())
                self.assertEqual(info['CFBundleIdentifier'], 'local.chanyoung.HappyLulu.Dev.manual-leave.20261015')
                self.assertEqual(info['CFBundleName'], 'happylulu-dev')
                self.assertEqual(info['CFBundleDisplayName'], 'happylulu-dev')
                self.assertEqual(Path(info['QAOutputPath']).parents[2].name, 'happylulu-dev.app')

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
                plist = output / "happylulu-dev.app/Contents/Info.plist"
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
