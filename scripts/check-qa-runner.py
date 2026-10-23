#!/usr/bin/env python3
"""Regression checks for QA reporting; no Swift build or personal data access."""
import importlib.util
import json
import os
import signal
import time
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

RUNNER = Path(__file__).with_name('run-qa.py')

class RunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        assert RUNNER.is_file(), 'QA runner must exist before execution/report tests can pass'
        spec = importlib.util.spec_from_file_location('qa_runner', RUNNER)
        cls.qa = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = cls.qa
        spec.loader.exec_module(cls.qa)

    def run_fixture(self, checks):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = self.qa.new_report_directory(root / 'reports')
            result = self.qa.execute(checks, root, report, {'profile': 'fixture'})
            written = json.loads((report / 'report.json').read_text())
            markdown = (report / 'summary.md').read_text()
            self.assertEqual(result, written)
            self.assertEqual(len(list((report / 'logs').glob('*.log'))), len(checks))
            return result, markdown

    def check(self, name, code, **kwargs):
        return self.qa.Check(name, [sys.executable, '-c', code], **kwargs)

    def test_success_has_command_duration_exit_and_report(self):
        result, markdown = self.run_fixture([self.check('ok', "print('PASS fixture')")])
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['exitCode'], 0)
        check = result['checks'][0]
        self.assertEqual(check['exitCode'], 0)
        self.assertGreaterEqual(check['durationSeconds'], 0)
        self.assertIn('-c', check['command'])
        self.assertIn('passed', markdown)

    def test_failure_does_not_prevent_independent_checks(self):
        result, _ = self.run_fixture([self.check('bad', 'raise SystemExit(7)'), self.check('later', "print('ok')")])
        self.assertEqual([c['status'] for c in result['checks']], ['failed', 'passed'])
        self.assertEqual(result['exitCode'], 1)
        self.assertEqual(result['checks'][0]['exitCode'], 7)

    def test_skip_is_partial_even_with_zero_exit(self):
        result, markdown = self.run_fixture([self.check('skip', "print('SKIP actual window unavailable')")])
        self.assertEqual(result['status'], 'partial')
        self.assertEqual(result['exitCode'], 0)
        self.assertIn('actual window unavailable', result['coverageGaps'][0])
        self.assertIn('partial', markdown)

    def test_embedded_skip_word_is_not_skip_marker(self):
        result, _ = self.run_fixture([self.check('ok', "print('PASS skipDisabled=1; do not SKIP this assertion')")])
        self.assertEqual(result['status'], 'passed')

    def test_limit_marker_is_partial_coverage_with_zero_exit(self):
        result, markdown = self.run_fixture([self.check('limited', "print('LIMIT native status button: selection background not captured')")])
        self.assertEqual(result['status'], 'partial')
        self.assertEqual(result['exitCode'], 0)
        self.assertIn('LIMIT native status button:', result['coverageGaps'][0])
        self.assertIn('partial', markdown)

    def test_embedded_limit_word_is_not_coverage_marker(self):
        result, _ = self.run_fixture([self.check('ok', "print('PASS capture LIMIT is only a word inside this line')")])
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['coverageGaps'], [])

    def test_skip_never_hides_failure(self):
        result, _ = self.run_fixture([self.check('bad', "print('SKIP no window'); raise SystemExit(9)")])
        self.assertEqual(result['checks'][0]['status'], 'failed')
        self.assertEqual(result['exitCode'], 1)

    def test_timeout_is_failure(self):
        result, _ = self.run_fixture([self.check('slow', 'import time; time.sleep(5)', timeout=0.05)])
        self.assertEqual(result['checks'][0]['status'], 'failed')
        self.assertEqual(result['checks'][0]['exitCode'], 124)
        self.assertIn('timeout', result['checks'][0]['reason'])

    def test_missing_command_is_blocked_and_fails_pipeline(self):
        result, _ = self.run_fixture([self.qa.Check('missing', ['/no/such/qa-command'])])
        self.assertEqual(result['checks'][0]['status'], 'blocked')
        self.assertEqual(result['exitCode'], 1)

    def test_failed_prebuild_blocks_dependent_only(self):
        result, _ = self.run_fixture([self.check('build', 'raise SystemExit(1)'), self.check('ui', "print('not run')", depends_on=('build',)), self.check('core', "print('ok')")])
        self.assertEqual([c['status'] for c in result['checks']], ['failed', 'blocked', 'passed'])
        self.assertIsNone(result['checks'][1]['exitCode'])

    def test_explicit_directory_cannot_reuse_stale_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            base = Path(folder)
            first = self.qa.new_report_directory(base)
            second = self.qa.new_report_directory(base)
            self.assertNotEqual(first, second)
            with self.assertRaises(FileExistsError):
                self.qa.new_report_directory(base, exact=first)

    def test_excluded_module_is_explicit_not_applicable(self):
        result, _ = self.run_fixture([self.qa.Check('optional', [], excluded='module excluded')])
        self.assertEqual(result['checks'][0]['status'], 'not-applicable')
        self.assertEqual(result['status'], 'passed')
        self.assertEqual(result['exitCode'], 0)

    def test_full_inventory_covers_original_workflow_checks(self):
        checks = self.qa.checks_for('full', Path(__file__).resolve().parent.parent)
        ids = [c.id for c in checks]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(len([i for i in ids if i.startswith('render-')]), 5)
        self.assertEqual(len([i for i in ids if i.startswith('core-')]), 6)
        self.assertIn('plugin-isolation', ids)
        self.assertIn('settings-navigation-legacy', ids)
        self.assertIn('daou-model', ids)
        self.assertIn('edit-menu', ids)
        self.assertIn('ai-tests', ids)
        self.assertIn('ai-ui', ids)

    def test_full_command_inventory_matches_original_ci(self):
        root = Path(__file__).resolve().parent.parent
        checks = self.qa.checks_for('full', root)
        actual = [tuple(c.command) for c in checks]
        swift = ['swift', 'run', '--build-system', 'native']
        expected = [tuple(swift + [product] + arguments) for product, arguments in [
            ('AfterSixChecks', []), ('AfterSixParityChecks', ['Tests/Shared/attendance.json']),
            ('CalendarSyncChecks', []), ('CalendarSyncServiceChecks', []),
            ('CPURunnerChecks', []), ('SystemMetricsChecks', []), ('AppPluginChecks', [])]]
        expected += [tuple(['swift', 'build', '--build-system', 'native', '--product', 'HappyLulu']),
                     tuple(['swift', 'test', '--build-system', 'native', '--filter', 'AIUsageTests'])]
        scripts = ['codex-symbol', 'ai-usage-ui'] + ['design-render'] * 5 + [
            'daouoffice-write', 'runner-artwork', 'owl-orbit', 'calendar-model',
            'calendar-diagnostics', 'calendar-runtime', 'automatic-install', 'runtime-profile',
            'clock-paste', 'panel-focus', 'appearance-model', 'settings-navigation',
            'settings-navigation', 'material-policy', 'plugin-architecture', 'vacation-eve',
            'vacation-appearance', 'plugin-isolation', 'daouoffice-model', 'edit-menu']
        expected += [('bash', 'scripts/check-' + name + '.sh') for name in scripts]
        self.assertCountEqual(actual, expected)
        self.assertEqual([c.env for c in checks if c.id.startswith('render-')], [
            {'HAPPY_LULU_SKIP_BUILD': '1', 'HAPPY_LULU_MATERIAL_MODE': 'legacy'},
            {'HAPPY_LULU_SKIP_BUILD': '1', 'HAPPY_LULU_MATERIAL_MODE': 'automatic'},
            {'HAPPY_LULU_SKIP_BUILD': '1', 'HAPPY_LULU_MATERIAL_MODE': 'automatic', 'HAPPY_LULU_RENDER_PALETTE': 'charcoal'},
            {'HAPPY_LULU_SKIP_BUILD': '1', 'HAPPY_LULU_RENDER_PALETTE': 'nativeGlass', 'HAPPY_LULU_RENDER_SCHEME': 'light'},
            {'HAPPY_LULU_SKIP_BUILD': '1', 'HAPPY_LULU_RENDER_PALETTE': 'nativeGlass', 'HAPPY_LULU_RENDER_SCHEME': 'dark', 'HAPPY_LULU_RENDER_EXPANDED': '1'},
        ])

    def test_evidence_inventory_only_includes_current_run(self):
        code = "import os; from pathlib import Path; p=Path(os.environ['HAPPY_LULU_RENDER_OUTPUT']); p.mkdir(parents=True, exist_ok=True); (p/'synthetic.png').write_bytes(b'fixture')"
        result, _ = self.run_fixture([self.check('image', code)])
        self.assertEqual(len(result['evidenceInventory']), 1)
        self.assertEqual(result['evidenceInventory'][0]['path'], 'evidence/image/synthetic.png')
        self.assertEqual(result['evidenceInventory'][0]['bytes'], 7)
        self.assertEqual(len(result['evidenceInventory'][0]['sha256']), 64)

    def test_artwork_scripts_receive_unique_evidence_argument(self):
        result, _ = self.run_fixture([self.check('owl-orbit', 'import sys; assert len(sys.argv) == 2')])
        self.assertEqual(result['status'], 'passed')
        self.assertTrue(result['checks'][0]['command'][-1].endswith('/evidence/owl-orbit'))

    def test_untracked_source_edit_changes_fingerprint(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'scripts').mkdir()
            source = root / 'scripts' / 'new.py'
            source.write_text('print(1)')
            before = self.qa.source_snapshot(root)
            source.write_text('print(2)')
            self.assertNotEqual(before, self.qa.source_snapshot(root))
            before_secret = self.qa.source_snapshot(root)
            (root / 'scripts' / '.env').write_text('secret=fixture')
            self.assertEqual(before_secret, self.qa.source_snapshot(root))
            self.assertNotIn('.env', self.qa.source_snapshot(root)['files'])

    def test_changed_source_during_run_invalidates_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            (root / 'scripts').mkdir()
            (root / 'scripts' / 'new.py').write_text('before')
            report = self.qa.new_report_directory(root / 'reports')
            snapshot = self.qa.source_snapshot(root)
            code = "from pathlib import Path; Path('scripts/new.py').write_text('after')"
            result = self.qa.execute([self.check('edit', code)], root, report, {'sourceFingerprint': snapshot['sha256']})
            self.assertEqual(result['status'], 'invalidated')
            self.assertEqual(result['exitCode'], 1)
            self.assertFalse(result['sourceUnchanged'])

    def test_all_existing_evidence_environment_hooks_are_isolated(self):
        keys = ['HAPPY_LULU_RENDER_OUTPUT', 'HAPPY_LULU_USAGE_EVIDENCE', 'HAPPY_LULU_NAVIGATION_EVIDENCE', 'HAPPY_LULU_EDIT_MENU_EVIDENCE', 'HAPPY_LULU_PANEL_CAPTURE_OUTPUT']
        code = 'import os; from pathlib import Path; keys=' + repr(keys) + '; assert all(Path(os.environ[k]).is_dir() and os.environ[k].endswith("/evidence/hooks") for k in keys)'
        result, _ = self.run_fixture([self.check('hooks', code)])
        self.assertEqual(result['status'], 'passed')

    def test_budget_finishes_report_and_blocks_remaining_checks(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = self.qa.new_report_directory(root / 'reports')
            checks = [self.check('slow', 'import time; time.sleep(5)'), self.check('remaining', "print('not run')")]
            result = self.qa.execute(checks, root, report, {}, budget=0.05)
            self.assertEqual([c['status'] for c in result['checks']], ['failed', 'blocked'])
            self.assertEqual(result['exitCode'], 1)
            self.assertIn('budget', result['checks'][1]['reason'])
            self.assertTrue((report / 'report.json').is_file())

    def test_termination_reaps_child_and_writes_interrupted_report(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            report = root / 'report'
            child_pid_file = root / 'child-pid'
            code = ("import importlib.util, pathlib, sys; "
                + 'spec=importlib.util.spec_from_file_location("qa", ' + repr(str(RUNNER)) + '); '
                + 'qa=importlib.util.module_from_spec(spec); sys.modules["qa"]=qa; spec.loader.exec_module(qa); '
                + 'root=pathlib.Path(' + repr(folder) + '); report=qa.new_report_directory(root, exact=root/"report"); '
                + "child=" + repr("import os, time; from pathlib import Path; Path('child-pid').write_text(str(os.getpid())); time.sleep(30)") + "; "
                + 'result=qa.execute([qa.Check("sleep", [sys.executable,"-c",child]), qa.Check("later",[sys.executable,"-c","print(1)"])],root,report,{}); sys.exit(result["exitCode"])')
            process = subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            child_pid = None
            try:
                deadline = time.monotonic() + 5
                while not child_pid_file.exists() and process.poll() is None and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(child_pid_file.exists(), 'fixture child must start before sending termination')
                child_pid = int(child_pid_file.read_text())
                process.send_signal(signal.SIGTERM)
                process.communicate(timeout=5)
                try:
                    os.kill(child_pid, 0)
                    alive = True
                except ProcessLookupError:
                    alive = False
                self.assertFalse(alive, 'runner must reap active child after termination')
                result = json.loads((report / 'report.json').read_text())
                self.assertEqual(result['exitCode'], 1)
                self.assertEqual([c['status'] for c in result['checks']], ['failed', 'blocked'])
            finally:
                if process.poll() is None:
                    process.kill()
                process.communicate()
                if child_pid is not None:
                    try:
                        os.kill(child_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_cli_unknown_profile_rejected(self):
        result = subprocess.run([sys.executable, str(RUNNER), '--profile', 'unknown'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

if __name__ == '__main__':
    unittest.main()
