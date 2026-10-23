#!/bin/bash
# Render actual app views using synthetic quota data and an isolated app identity.
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
if [[ "${HAPPY_LULU_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --build-system native --product HappyLulu >/dev/null
fi
build_dir="$(swift build --build-system native --show-bin-path)"
frameworks="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp/}HappyLulu-usage-ui.XXXXXX")"
bundle_id=""
cleanup() {
  if [[ -n "$bundle_id" ]]; then
    /usr/bin/defaults delete "$bundle_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$probe_dir"
}
trap cleanup EXIT
app="$probe_dir/UsageProbe.app"
if [[ "$interactive" == "1" ]]; then app="$probe_dir/HappyLulu QA Synthetic.app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$probe_dir/data"
cp Resources/HappyLuluBrand.png "$app/Contents/Resources/"
cp -R Resources/OwlStates "$app/Contents/Resources/"
ditto "$build_dir/HappyLulu_CPURunnerIntegration.bundle" "$app/Contents/Resources/HappyLulu_CPURunnerIntegration.bundle"
python3 - Sources/AfterSix/AppearanceModel.swift "$probe_dir/AppearanceModel.swift" "$app/Contents/Info.plist" <<'PY'
import pathlib, plistlib, sys, uuid
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'static let shared = AppearanceModel()'
assert source.count(needle) == 1
replacement = '''static let shared = AppearanceModel(store: AppearanceStore(rootDirectory: URL(fileURLWithPath: CommandLine.arguments[1]), bundleIdentifier: Bundle.main.bundleIdentifier!), originalIcon: NSImage(contentsOfFile: CommandLine.arguments[2])!)'''
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, replacement))
with pathlib.Path(sys.argv[3]).open('wb') as stream:
    plistlib.dump(dict(CFBundleIdentifier='local.happylulu.usage-probe.' + uuid.uuid4().hex,
        CFBundleExecutable='UsageProbe', CFBundleName='UsageProbe', CFBundlePackageType='APPL',
        LSUIElement=True, HappyLuluUpdateServiceEnabled=False), stream)
PY
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")"
plugin_manager_source="Sources/AfterSix/PluginManagerModel.swift"
probe_sources=(Tests/AIUsageUIProbe/main.swift)
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
plist = probe / 'HappyLulu QA Synthetic.app/Contents/Info.plist'
info = plistlib.loads(plist.read_bytes())
info.update(CFBundleName='HappyLulu QA Synthetic', CFBundleDisplayName='HappyLulu QA Synthetic', LSUIElement=False)
plist.write_bytes(plistlib.dumps(info))
PYFIXTURE
  plugin_manager_source="$probe_dir/PluginManagerModel.swift"
  probe_sources+=("$probe_dir/AIUsageSettingsView.swift")
fi
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$PWD/.build/ai-usage-ui-module-cache" \
  -I "$build_dir/Modules" -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
  Sources/AfterSix/AppLanguage.swift Sources/AfterSix/AppModel.swift Sources/AfterSix/AppUpdater.swift \
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
  echo "QA preferences: $bundle_id (removed on exit)"
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
