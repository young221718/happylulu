#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${HAPPY_LULU_MATERIAL_MODE:-automatic}" in
  automatic|legacy) ;;
  *) echo "HAPPY_LULU_MATERIAL_MODE must be automatic or legacy" >&2; exit 64 ;;
esac
if [[ "${HAPPY_LULU_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --build-system native --product HappyLulu >/dev/null
fi
build_dir="${HAPPY_LULU_BUILD_DIR:-}"
if [[ -z "$build_dir" ]]; then
  build_dir="$(swift build --build-system native --show-bin-path)"
fi
frameworks="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp/}HappyLulu-settings-navigation.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
mkdir -p "$probe_dir/data"
python3 - "${HAPPY_LULU_PROBE_APPEARANCE_SOURCE:-Sources/AfterSix/AppearanceModel.swift}" "$probe_dir/AppearanceModel.swift" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'static let shared = AppearanceModel()'
assert source.count(needle) == 1
# Only redirect the shared instance's storage and source icon; production view/model behavior is unchanged.
replacement = '''static let shared = AppearanceModel(store: AppearanceStore(rootDirectory: URL(fileURLWithPath: CommandLine.arguments[1]), bundleIdentifier: "isolated-storage"), originalIcon: NSImage(contentsOfFile: CommandLine.arguments[2])!)'''
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, replacement))
PY
python3 - Sources/AfterSix/AppearanceSettingsView.swift "$probe_dir/AppearanceSettingsView.swift" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
# Instrument the real group bounds only in this isolated test process.
for name in ('theme', 'icons'):
    needle = f'.accessibilityIdentifier("appearance-{name}")'
    assert source.count(needle) == 1
    measure = f'''.background {{ GeometryReader {{ proxy in
        Color.clear.preference(key: AppearanceFramesKey.self,
            value: ["{name}": proxy.frame(in: .named("appearance-layout"))])
    }} }}'''
    source = source.replace(needle, needle + '\n                ' + measure)
pathlib.Path(sys.argv[2]).write_text(source)
PY
python3 - "${HAPPY_LULU_PROBE_SETTINGS_SOURCE:-Sources/AfterSix/SettingsView.swift}" "$probe_dir/SettingsView.swift" <<'PY'
import os, pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
# Expand only in the isolated render to check long Korean/English help without changing app preferences.
if os.environ.get('HAPPY_LULU_EXPANDED_HELP') == '1':
    for label in ('L("표시 방식 안내", "About display formats")',
                  'L("단축 근무와 반차 안내", "About shorter days and half-days")',
                  'L("업데이트 동작 안내", "About updates")'):
        needle = 'DisclosureGroup(' + label + ')'
        assert source.count(needle) == 1
        source = source.replace(needle, 'DisclosureGroup(' + label + ', isExpanded: .constant(true))')
needle = '''.padding(.horizontal, SettingsLayout.rowHorizontal).padding(.vertical, SettingsLayout.rowVertical)
        .frame(maxWidth: .infinity, alignment: .leading)'''
assert source.count(needle) == 1
measure = '''.background { GeometryReader { proxy in
            Color.clear.preference(key: GeneralFramesKey.self,
                value: [title: proxy.frame(in: .named("appearance-layout"))])
        } }'''
source = source.replace(needle, needle + '\n        ' + measure)
needle = '            control()'
assert source.count(needle) == 1
measure = '''.background { GeometryReader { proxy in
                Color.clear.preference(key: GeneralFramesKey.self,
                    value: ["control:" + title: proxy.frame(in: .named("appearance-layout"))])
            } }'''
source = source.replace(needle, needle + '\n            ' + measure)
needle = '.accessibilityIdentifier(id == "ai-usage" ? "settings-usage-switch" : "settings-plugin-switch-\\(id)")'
assert source.count(needle) == 1
measure = '''.background { GeometryReader { proxy in
            Color.clear.preference(key: UsageControlFramesKey.self,
                value: ["usage": proxy.frame(in: .named("appearance-layout"))])
        } }'''
source = source.replace(needle, needle + '\n        ' + measure)
for name in ('page-title', 'page-content', 'updates', 'history'):
    needle = f'.accessibilityIdentifier("settings-{name}")'
    assert source.count(needle) == 1
    key = 'title:\\(pageTitle)' if name == 'page-title' else name
    measure = f'''.background {{ GeometryReader {{ proxy in
        Color.clear.preference(key: SettingsPageFramesKey.self,
            value: ["{key}": proxy.frame(in: .named("appearance-layout"))])
    }} }}'''
    source = source.replace(needle, needle + '\n        ' + measure)
pathlib.Path(sys.argv[2]).write_text(source)
PY
swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macosx13.0" -module-cache-path "$PWD/.build/settings-navigation-module-cache" \
  -I "$build_dir/Modules" -F "$frameworks" -Xlinker -rpath -Xlinker "$frameworks" \
  Sources/AfterSix/AppLanguage.swift Sources/AfterSix/AppModel.swift Sources/AfterSix/AppUpdater.swift \
  Sources/AfterSix/LuluBrand.swift \
  Sources/AfterSix/LuluMaterials.swift \
  Sources/AfterSix/CalendarSyncModel.swift Sources/AfterSix/HalfDayCalendarReader.swift \
  Sources/AfterSix/DefaultFeatureAdapter.swift Sources/AfterSix/PluginManagerModel.swift \
  Sources/AfterSix/BundledPlugins.swift Sources/AfterSix/FeatureCalendarModel.swift \
  Sources/AfterSix/SettingsStyle.swift Sources/AfterSix/PluginSettingsView.swift "$probe_dir/SettingsView.swift" Sources/AfterSix/SettingsWindowChrome.swift \
  "$probe_dir/AppearanceSettingsView.swift" Sources/AfterSix/AttendanceCalendarView.swift \
  Sources/AfterSix/AttendanceControlsView.swift Sources/AfterSix/TodayDayTypeView.swift \
  Sources/AfterSix/FeatureCalendarView.swift Sources/AfterSix/CalendarWorkspaceView.swift \
  Sources/AfterSix/CalendarSyncSettingsView.swift "$probe_dir/AppearanceModel.swift" Tests/SettingsNavigationProbe/main.swift \
  "$build_dir"/AppPluginCore.build/*.swift.o "$build_dir"/AppPluginHost.build/*.swift.o \
  "$build_dir"/CPURunnerIntegration.build/*.swift.o \
  "$build_dir"/MacUtilitiesIntegration.build/*.swift.o \
  "$build_dir"/AfterSixCore.build/*.swift.o "$build_dir"/CalendarSyncServices.build/*.swift.o \
  "$build_dir"/CalendarSyncCore.build/*.swift.o \
  -framework AppKit -framework SwiftUI -framework CoreImage -framework Security \
  -framework EventKit -framework ServiceManagement -framework Sparkle -lsqlite3 \
  -o "$probe_dir/navigation-check"
status=0
"$probe_dir/navigation-check" "$probe_dir/data" "$PWD/Resources/HappyLuluIcon.png" || status=$?
if [[ -n "${HAPPY_LULU_NAVIGATION_EVIDENCE:-}" ]]; then
  mkdir -p "$HAPPY_LULU_NAVIGATION_EVIDENCE"
  cp "$probe_dir/data/"*.png "$HAPPY_LULU_NAVIGATION_EVIDENCE/"
fi
exit "$status"
