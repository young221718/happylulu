#!/usr/bin/env python3
"""Run HappyLulu's existing isolated checks and retain an honest QA report."""
from __future__ import annotations
import argparse
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import signal
import subprocess
import sys
import time
import uuid


@dataclass
class Check:
    id: str
    command: list[str]
    timeout: float = 600
    env: dict[str, str] = field(default_factory=dict)
    depends_on: tuple[str, ...] = ()
    excluded: str | None = None


def new_report_directory(base, exact=None):
    directory = Path(exact) if exact else Path(base) / (datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
    directory.mkdir(parents=True, exist_ok=False)
    (directory / 'logs').mkdir()
    (directory / 'evidence').mkdir()
    return directory.resolve()


def checks_for(profile, root):
    swift = ['swift', 'run', '--build-system', 'native']
    checks = [Check('core-' + name, swift + [product] + args) for name, product, args in [
        ('attendance', 'AfterSixChecks', []),
        ('parity', 'AfterSixParityChecks', ['Tests/Shared/attendance.json']),
        ('calendar', 'CalendarSyncChecks', []),
        ('calendar-service', 'CalendarSyncServiceChecks', []),
        ('cpu-runner', 'CPURunnerChecks', []),
        ('system-metrics', 'SystemMetricsChecks', []),
    ]]
    checks.append(Check('app-build', ['swift', 'build', '--build-system', 'native', '--product', 'HappyLulu']))

    def script(identifier, name, env=None):
        return Check(identifier, ['bash', 'scripts/check-' + name + '.sh'], env=env or {}, depends_on=('app-build',))

    ai_present = (os.environ.get('HAPPY_LULU_DISABLE_AI_USAGE') != '1' and all((root / 'Sources' / name).is_dir() for name in ('AIUsagePlugin', 'AIUsageIntegration')))
    ai_reason = None if ai_present else 'AI usage module excluded by source composition or HAPPY_LULU_DISABLE_AI_USAGE=1'
    if profile == 'full':
        checks.append(Check('ai-tests', ['swift', 'test', '--build-system', 'native', '--filter', 'AIUsageTests'], excluded=ai_reason))
    for identifier, name in [('codex-symbol', 'codex-symbol'), ('ai-ui', 'ai-usage-ui')]:
        check = script(identifier, name, {'HAPPY_LULU_SKIP_BUILD': '1'})
        check.excluded = ai_reason
        checks.append(check)
    if profile == 'smoke':
        checks.extend([script('clock-paste', 'clock-paste'), script('material-policy', 'material-policy')])
        return checks

    for identifier, settings in [
        ('render-legacy', {'HAPPY_LULU_MATERIAL_MODE': 'legacy'}),
        ('render-automatic', {'HAPPY_LULU_MATERIAL_MODE': 'automatic'}),
        ('render-charcoal', {'HAPPY_LULU_MATERIAL_MODE': 'automatic', 'HAPPY_LULU_RENDER_PALETTE': 'charcoal'}),
        ('render-native-light', {'HAPPY_LULU_RENDER_PALETTE': 'nativeGlass', 'HAPPY_LULU_RENDER_SCHEME': 'light'}),
        ('render-native-dark-expanded', {'HAPPY_LULU_RENDER_PALETTE': 'nativeGlass', 'HAPPY_LULU_RENDER_SCHEME': 'dark', 'HAPPY_LULU_RENDER_EXPANDED': '1'}),
    ]:
        checks.append(script(identifier, 'design-render', {'HAPPY_LULU_SKIP_BUILD': '1', **settings}))
    for name in ['daouoffice-write', 'runner-artwork', 'owl-orbit', 'calendar-model', 'calendar-diagnostics', 'calendar-runtime', 'automatic-install', 'runtime-profile', 'clock-paste', 'panel-focus', 'appearance-model', 'settings-navigation']:
        checks.append(script(name, name))
    checks.append(script('settings-navigation-legacy', 'settings-navigation', {'HAPPY_LULU_MATERIAL_MODE': 'legacy'}))
    for name in ['material-policy', 'plugin-architecture', 'vacation-eve', 'vacation-appearance', 'plugin-isolation']:
        checks.append(script(name, name))
    daou_present = (os.environ.get('HAPPY_LULU_DISABLE_DAOUOFFICE') != '1' and all((root / 'Sources' / name).is_dir() for name in ('DaouOfficePlugin', 'DaouOfficeIntegration')))
    daou_reason = None if daou_present else 'Daouoffice module excluded by source composition or HAPPY_LULU_DISABLE_DAOUOFFICE=1'
    checks.append(Check('app-plugin', swift + ['AppPluginChecks'], excluded=daou_reason))
    for identifier, name in [('daou-model', 'daouoffice-model'), ('edit-menu', 'edit-menu')]:
        check = script(identifier, name)
        check.excluded = daou_reason
        checks.append(check)
    return checks


def source_snapshot(root):
    roots = ['Sources', 'Tests', 'scripts', '.github', 'Resources', 'Package.swift', 'Package.resolved']
    names = subprocess.check_output(['git', 'ls-files', '-z', '--cached', '--others', '--exclude-standard', '--', *roots], cwd=root).split(b'\0')
    allowed = {'.swift', '.py', '.sh', '.yml', '.yaml', '.plist', '.png', '.svg', '.xcassets', '.c', '.h', '.m', '.mm', '.cpp', '.strings', '.stringsdict', '.gif', '.icns', '.ico'}
    files = {}
    for raw in sorted(set(names)):
        if not raw:
            continue
        name = os.fsdecode(raw)
        path = root / name
        fixture_json = name.startswith(('Tests/', 'Resources/')) and path.suffix == '.json'
        if path.suffix not in allowed and name not in ('Package.swift', 'Package.resolved') and not fixture_json:
            continue
        if path.is_symlink():
            files[name] = 'symlink:' + os.readlink(path)
        else:
            files[name] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else 'deleted'
    digest = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    return {'sha256': digest, 'files': files}


def tool_metadata():
    versions = {}
    for name, command in [('swift', ['swift', '--version']), ('sdk', ['xcrun', '--show-sdk-version']), ('developerDirectory', ['xcode-select', '-p'])]:
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=10)
            versions[name] = result.stdout.strip() if result.returncode == 0 else 'unavailable (exit ' + str(result.returncode) + ')'
        except (OSError, subprocess.TimeoutExpired):
            versions[name] = 'unavailable'
    return versions


def source_metadata(root, profile):
    def git(*args):
        return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.DEVNULL)
    status = git('status', '--porcelain=v1', '--untracked-files=normal')
    snapshot = source_snapshot(root)
    return {
        'profile': profile,
        'gitSHA': git('rev-parse', 'HEAD').decode().strip(),
        'dirty': bool(status),
        'sourceFingerprint': snapshot['sha256'],
        'sourceFiles': snapshot['files'],
        'fingerprintScope': 'nonignored source/build code and reviewed resource files in Sources/Tests/scripts/.github/Resources plus Package.swift/resolved, including untracked code',
        'environment': {
            'system': platform.system(), 'release': platform.release(),
            'machine': platform.machine(), 'python': platform.python_version(),
            **tool_metadata(),
            **{key: os.environ[key] for key in ('CI', 'GITHUB_ACTIONS', 'HAPPY_LULU_DISABLE_AI_USAGE', 'HAPPY_LULU_DISABLE_DAOUOFFICE') if key in os.environ},
        },
    }


def write_report(report, result):
    result['evidenceInventory'] = [{'path': str(path.relative_to(report)), 'bytes': path.stat().st_size,
        'sha256': hashlib.sha256(path.read_bytes()).hexdigest()} for path in sorted((report / 'evidence').rglob('*')) if path.is_file()]
    (report / 'report.json').write_text(json.dumps(result, indent=2, ensure_ascii=False) + '\n')
    lines = ['# HappyLulu QA', '', f"Status: **{result['status']}** (automation exit {result['exitCode']})", '',
        f"Profile: `{result.get('profile', 'unknown')}`", f"Source: `{result.get('gitSHA', 'fixture')}`", '',
        'Passing automated checks do not prove live account connections, user permissions, real menu clicks, reboot/login behavior, or visual acceptance.', '',
        '| Check | Result | Seconds | Exit | Log |', '| --- | --- | ---: | ---: | --- |']
    for check in result['checks']:
        lines.append(f"| {check['id']} | {check['status']} | {check['durationSeconds']:.2f} | {check['exitCode'] if check['exitCode'] is not None else '—'} | [{check['id']}](logs/{check['id']}.log) |")
    if result['coverageGaps']:
        lines += ['', '## Coverage gaps', '', 'The run is partial. Exit 0 means no required command failed; it does not mean complete QA coverage.', '']
        lines += ['- ' + gap.replace('\n', ' ') for gap in result['coverageGaps']]
    lines += ['', '## Remaining live acceptance', '', '- Actual clipboard shortcuts and context-menu actions in the installed app.', '- Calendar full-access permission and a successful read; Daouoffice Keychain approval and a successful refresh.', '- Real menu-bar interactions, appearance review, and login after reboot (requires operator approval).', '']
    (report / 'summary.md').write_text('\n'.join(lines))


def execute(checks, root, report, metadata, budget=1500):
    started = datetime.now(timezone.utc).isoformat()
    results = []
    gaps = []
    deadline = time.monotonic() + budget
    abort_reason = None
    previous_term = signal.getsignal(signal.SIGTERM)
    def interrupt(signum, frame):
        raise KeyboardInterrupt
    signal.signal(signal.SIGTERM, interrupt)
    for index, check in enumerate(checks):
        start = time.monotonic()
        entry = {'id': check.id, 'command': check.command, 'environment': check.env,
                 'status': 'passed', 'durationSeconds': 0, 'exitCode': None,
                 'log': 'logs/' + check.id + '.log', 'coverageGaps': []}
        evidence = report / 'evidence' / check.id
        if check.id in ('runner-artwork', 'owl-orbit', 'vacation-appearance'):
            entry['command'] = check.command + [str(evidence)]
        log_path = report / entry['log']
        dependency_failures = [dep for dep in check.depends_on if not any(item['id'] == dep and item['status'] in ('passed', 'partial') for item in results)]
        if check.excluded:
            entry.update(status='not-applicable', reason=check.excluded)
            log_path.write_text(check.excluded + '\n')
        elif abort_reason or time.monotonic() >= deadline:
            abort_reason = abort_reason or 'QA time budget exhausted'
            entry.update(status='blocked', reason=abort_reason)
            log_path.write_text(abort_reason + '\n')
        elif dependency_failures:
            entry.update(status='blocked', reason='prerequisite did not pass: ' + ', '.join(dependency_failures))
            log_path.write_text(entry['reason'] + '\n')
        else:
            env = os.environ.copy()
            # Evidence and material overrides must not leak between rendering variants.
            for key in ('HAPPY_LULU_MATERIAL_MODE', 'HAPPY_LULU_RENDER_PALETTE', 'HAPPY_LULU_RENDER_SCHEME', 'HAPPY_LULU_RENDER_EXPANDED', 'HAPPY_LULU_RENDER_OUTPUT', 'HAPPY_LULU_USAGE_EVIDENCE', 'HAPPY_LULU_NAVIGATION_EVIDENCE', 'HAPPY_LULU_EDIT_MENU_EVIDENCE', 'HAPPY_LULU_PANEL_CAPTURE_OUTPUT', 'HAPPY_LULU_SKIP_BUILD'):
                env.pop(key, None)
            env.update(check.env)
            env['HAPPY_LULU_RENDER_OUTPUT'] = str(evidence)
            env['HAPPY_LULU_USAGE_EVIDENCE'] = str(evidence)
            for key in ('HAPPY_LULU_NAVIGATION_EVIDENCE', 'HAPPY_LULU_EDIT_MENU_EVIDENCE', 'HAPPY_LULU_PANEL_CAPTURE_OUTPUT'):
                env[key] = str(evidence)
            evidence.mkdir(parents=True, exist_ok=True)
            print('BEGIN ' + check.id, flush=True)
            with log_path.open('w') as log:
                log.write('$ ' + shlex.join(entry['command']) + '\n')
                log.flush()
                process = None
                try:
                    process = subprocess.Popen(entry['command'], cwd=root, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                    try:
                        entry['exitCode'] = process.wait(timeout=min(check.timeout, max(0.001, deadline - time.monotonic())))
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
                        if time.monotonic() >= deadline:
                            abort_reason = 'QA time budget exhausted'
                        entry.update(exitCode=124, reason=abort_reason or f'timeout after {check.timeout:g} seconds')
                        log.write('\nFAIL ' + entry['reason'] + '\n')
                except KeyboardInterrupt:
                    if process is not None:
                        try:
                            os.killpg(process.pid, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                        process.wait()
                    abort_reason = 'QA interrupted by operator or termination signal'
                    entry.update(exitCode=130, reason=abort_reason)
                    log.write('\nFAIL ' + abort_reason + '\n')
                except OSError as error:
                    entry.update(status='blocked', reason=str(error))
                    log.write('\nBLOCKED ' + str(error) + '\n')
            output = log_path.read_text(errors='replace')
            skipped = [line.strip() for line in output.splitlines() if re.match(r'^\s*(?:SKIP|LIMIT)(?:\s|:|$)', line)]
            entry['coverageGaps'] = skipped
            gaps.extend(check.id + ': ' + line for line in skipped)
            if entry['status'] != 'blocked':
                entry['status'] = 'failed' if entry['exitCode'] != 0 else ('partial' if skipped else 'passed')
        entry['durationSeconds'] = round(time.monotonic() - start, 3)
        results.append(entry)
        print(f"END {check.id}: {entry['status']} ({entry['durationSeconds']:.2f}s)", flush=True)
        failed = any(item['status'] in ('failed', 'blocked') for item in results)
        result = {**metadata, 'startedAt': started, 'finishedAt': datetime.now(timezone.utc).isoformat(),
                  'status': 'running' if index + 1 < len(checks) else ('failed' if failed else ('partial' if gaps else 'passed')),
                  'exitCode': 1 if failed else 0, 'plannedCheckCount': len(checks), 'completedCheckCount': len(results), 'checks': results, 'coverageGaps': gaps,
                  'manualAcceptanceRequired': True}
        write_report(report, result)
    if 'sourceFingerprint' in metadata:
        final_snapshot = source_snapshot(root)
        result['finalSourceFingerprint'] = final_snapshot['sha256']
        result['sourceUnchanged'] = metadata['sourceFingerprint'] == final_snapshot['sha256']
        if not result['sourceUnchanged']:
            result.update(status='invalidated', exitCode=1)
            result['coverageGaps'].append('Source changed during QA; rerun against a stable source snapshot.')
        write_report(report, result)
    signal.signal(signal.SIGTERM, previous_term)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=('smoke', 'full'), default='smoke')
    parser.add_argument('--report-dir', '--output', dest='report_dir', type=Path, help='new exact directory; refuses existing directories')
    parser.add_argument('--list', action='store_true', help='show commands without running checks')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    checks = checks_for(args.profile, root)
    if args.list:
        for check in checks:
            print(check.id + ': ' + (check.excluded or shlex.join(check.command)))
        return 0
    metadata = source_metadata(root, args.profile)
    report = new_report_directory(root / '.build' / 'qa', args.report_dir)
    print('QA report: ' + str(report), flush=True)
    result = execute(checks, root, report, metadata)
    print(f"QA {result['status']}: {report / 'summary.md'}", flush=True)
    return result['exitCode']


if __name__ == '__main__':
    sys.exit(main())
