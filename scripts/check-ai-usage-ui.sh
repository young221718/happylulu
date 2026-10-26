#!/bin/bash
# Render actual app views using synthetic data under the single development identity.
set -euo pipefail
cd "$(dirname "$0")/.."
interactive=0
case "$#:${1:-}" in
  0:) ;;
  1:--interactive) interactive=1 ;;
  1:--help)
    echo "Usage: $0 [--interactive]"
    echo "Default: automated synthetic UI checks (120-second timeout)."
    echo "--interactive: hold isolated synthetic settings/panel until Quit; forbidden in CI."
    exit 0 ;;
  *) echo "Usage: $0 [--interactive]" >&2; exit 64 ;;
esac
if [[ "$interactive" == "1" && ( -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" ) ]]; then
  echo "interactive UI QA cannot run in CI" >&2
  exit 64
fi
case "${HAPPY_LULU_MATERIAL_MODE:-automatic}" in
  automatic|legacy) ;;
  *) echo "HAPPY_LULU_MATERIAL_MODE must be automatic or legacy" >&2; exit 64 ;;
esac
probe_root="${TMPDIR:-/tmp}"
probe_dir="${probe_root%/}/happylulu-dev-synthetic"
lock_dir="$probe_dir.lock"
umask 077
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "happylulu-dev synthetic QA is already running (lock: $lock_dir)" >&2
  exit 73
fi
if [[ -e "$probe_dir" || -L "$probe_dir" ]]; then
  echo "happylulu-dev synthetic QA has leftover files; preserve or remove $probe_dir before retrying" >&2
  rmdir "$lock_dir"
  exit 73
fi
lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
cleanup() {
  local result=$?
  if [[ -n "${app:-}" && -x "$app/Contents/MacOS/UsageProbe" ]]; then
    if ! "$lsregister" -u "$app"; then
      echo "FAIL happylulu-dev cleanup: unregister failed; bundle and lock preserved at $probe_dir" >&2
      exit 1
    fi
  fi
  rm -rf "$probe_dir"
  rmdir "$lock_dir"
  exit "$result"
}
trap cleanup EXIT
mkdir -p "$probe_dir"
if [[ "${HAPPY_LULU_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --build-system native --product HappyLulu >/dev/null
fi
build_dir="$(swift build --build-system native --show-bin-path)"
frameworks="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
app="$probe_dir/happylulu-dev.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$probe_dir/data"
cp Resources/HappyLuluBrand.png "$app/Contents/Resources/"
cp -R Resources/OwlStates "$app/Contents/Resources/"
ditto "$build_dir/HappyLulu_CPURunnerIntegration.bundle" "$app/Contents/Resources/HappyLulu_CPURunnerIntegration.bundle"
python3 - Sources/AfterSix/AppearanceModel.swift "$probe_dir/AppearanceModel.swift" "$app/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'static let shared = AppearanceModel()'
assert source.count(needle) == 1
replacement = '''static let shared = AppearanceModel(store: AppearanceStore(rootDirectory: URL(fileURLWithPath: CommandLine.arguments[1]), bundleIdentifier: Bundle.main.bundleIdentifier!), originalIcon: NSImage(contentsOfFile: CommandLine.arguments[2])!)'''
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, replacement))
for name, count in [('AppLanguage', 3), ('AppModel', 2)]:
    source = pathlib.Path('Sources/AfterSix/' + name + '.swift').read_text()
    assert source.count('UserDefaults.standard') == count
    if name == 'AppModel':
        for old, new in [('CountdownDisplay.saved()', 'CountdownDisplay.saved(in: ProbePreferences.shared)'),
                         ('choice.save()', 'choice.save(in: ProbePreferences.shared)')]:
            assert source.count(old) == 1
            source = source.replace(old, new)
    pathlib.Path(sys.argv[2]).with_name(name + '.swift').write_text(
        source.replace('UserDefaults.standard', 'ProbePreferences.shared'))
with pathlib.Path(sys.argv[3]).open('wb') as stream:
    plistlib.dump(dict(CFBundleIdentifier='local.chanyoung.HappyLulu.Dev.manual-leave.20261015',
        CFBundleExecutable='UsageProbe', CFBundleName='happylulu-dev', CFBundleDisplayName='happylulu-dev', CFBundlePackageType='APPL',
        LSUIElement=True, HappyLuluUpdateServiceEnabled=False), stream)
PY
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
plugin_manager_source="Sources/AfterSix/PluginManagerModel.swift"
probe_sources=(Tests/AIUsageUIProbe/main.swift Tests/AIUsageUIProbe/ProbePreferences.swift)
if [[ "$interactive" == "1" ]]; then
  # Copies restrict this held fixture only; automatic checks compile unchanged production views.
  python3 - "$probe_dir" <<'PYFIXTURE'
import pathlib, plistlib, sys
probe = pathlib.Path(sys.argv[1])
source = pathlib.Path('Sources/AfterSix/PluginManagerModel.swift').read_text()
needle = '        factories["mac-calendar"] = { [weak self, weak sync] in'
assert source.count(needle) == 1
source = source.replace(needle, '        catalog.removeAll { !["ai-usage", "cpu-runner"].contains($0.id) }\n' + needle)
(probe / 'PluginManagerModel.swift').write_text(source)
source = 'import AIUsageIntegration\n' + pathlib.Path('Sources/AIUsageIntegration/AIUsageSettingsView.swift').read_text()
needle = '.labelsHidden().toggleStyle(.switch)'
assert source.count(needle) == 1
source = source.replace(needle, needle + '.disabled(true).help("Synthetic QA: system notification permission is not exercised")')
(probe / 'AIUsageSettingsView.swift').write_text(source)
plist = probe / 'happylulu-dev.app/Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(LSUIElement=False)
plist.write_bytes(plistlib.dumps(info))
PYFIXTURE
  plugin_manager_source="$probe_dir/PluginManagerModel.swift"
  probe_sources+=("$probe_dir/AIUsageSettingsView.swift")
fi
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$PWD/.build/ai-usage-ui-module-cache" \
  -I "$build_dir/Modules" -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
  "$probe_dir/AppLanguage.swift" "$probe_dir/AppModel.swift" Sources/AfterSix/AppUpdater.swift \
  Sources/AfterSix/LuluBrand.swift Sources/AfterSix/ApplicationMenu.swift \
  Sources/AfterSix/LuluMaterials.swift Sources/AfterSix/MenuBarPanel.swift Sources/AfterSix/SettingsWindowChrome.swift \
  Sources/AfterSix/CalendarSyncModel.swift Sources/AfterSix/HalfDayCalendarReader.swift \
  Sources/AfterSix/DefaultFeatureAdapter.swift "$plugin_manager_source" \
  Sources/AfterSix/BundledPlugins.swift Sources/AfterSix/FeatureCalendarModel.swift \
  Sources/AfterSix/PluginSettingsView.swift Sources/AfterSix/SettingsView.swift \
  Sources/AfterSix/AppearanceSettingsView.swift Sources/AfterSix/AttendanceCalendarView.swift \
  Sources/AfterSix/AttendanceControlsView.swift Sources/AfterSix/TodayDayTypeView.swift \
  Sources/AfterSix/FeatureCalendarView.swift Sources/AfterSix/CalendarWorkspaceView.swift \
  Sources/AfterSix/TodayAgendaView.swift Sources/AfterSix/ArrivalClockDigitField.swift Sources/AfterSix/PanelView.swift \
  Sources/AfterSix/CalendarSyncSettingsView.swift "$probe_dir/AppearanceModel.swift" "${probe_sources[@]}" \
  "$build_dir"/AppPluginCore.build/*.swift.o "$build_dir"/AppPluginHost.build/*.swift.o \
  "$build_dir"/AfterSixCore.build/*.swift.o "$build_dir"/CalendarSyncServices.build/*.swift.o \
  "$build_dir"/CalendarSyncCore.build/*.swift.o "$build_dir"/AIUsagePlugin.build/*.swift.o \
  "$build_dir"/AIUsageIntegration.build/*.swift.o \
  "$build_dir"/CPURunnerIntegration.build/*.swift.o \
  -framework AppKit -framework SwiftUI -framework CoreImage -framework Security -framework IOKit -framework SystemConfiguration \
  -framework EventKit -framework ServiceManagement -framework UserNotifications -framework Sparkle -lsqlite3 \
  -o "$app/Contents/MacOS/UsageProbe"
if [[ "$interactive" == "1" ]]; then
  echo "SYNTHETIC QA — no live Codex, Calendar, Keychain, login-item or update services"
  echo "QA app: $app"
  echo "QA data: $probe_dir/data"
  echo "QA preferences: memory only; existing $bundle_id preferences are preserved"
  echo "Quit the QA app (Command-Q or panel → Quit) to stop and remove this fixture."
  python3 - "$app/Contents/MacOS/UsageProbe" "$probe_dir/data" "$PWD/Resources/HappyLuluIcon.png" --interactive <<'PYINTERACTIVE'
import subprocess, sys
process = subprocess.Popen(sys.argv[1:])
try:
    result = process.wait()
except KeyboardInterrupt:
    process.terminate()
    process.wait(timeout=5)
    result = 130
sys.exit(result if result >= 0 else 128 - result)
PYINTERACTIVE
  exit "$?"
fi
status=0
python3 - "$app/Contents/MacOS/UsageProbe" "$probe_dir/data" "$PWD/Resources/HappyLuluIcon.png" <<'PYTIMEOUT' || status=$?
import subprocess, sys
try:
    result = subprocess.run(sys.argv[1:], timeout=120)
except subprocess.TimeoutExpired:
    print("FAIL usage UI: probe exceeded 120 seconds; last BEGIN line identifies the blocked operation", file=sys.stderr)
    sys.exit(124)
sys.exit(result.returncode if result.returncode >= 0 else 128 - result.returncode)
PYTIMEOUT
if [[ -n "${HAPPY_LULU_USAGE_EVIDENCE:-}" ]]; then
  mkdir -p "$HAPPY_LULU_USAGE_EVIDENCE"
  cp "$probe_dir/data/"*.png "$HAPPY_LULU_USAGE_EVIDENCE/"
fi
exit "$status"
