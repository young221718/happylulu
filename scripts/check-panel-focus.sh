#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --build-system native --product HappyLulu >/dev/null
build_dir="$(swift build --build-system native --show-bin-path)"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp/}HappyLulu-panel-focus.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
# A command-line hosting process does not register another macOS app identity.
python3 - Sources/AfterSix/AppLanguage.swift "$probe_dir/AppLanguage.swift" <<'PYLANG'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'UserDefaults.standard.set(choice.rawValue, forKey: Self.key)'
assert source.count(needle) == 1
replacement = 'UserDefaults.standard.setVolatileDomain([Self.key: choice.rawValue], forName: UserDefaults.argumentDomain)'
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, replacement))
PYLANG
# Keep shared appearance initialization isolated while compiling the actual panel and model sources.
python3 - Sources/AfterSix/AppearanceModel.swift "$probe_dir/AppearanceModel.swift" "$probe_dir" <<'PY'
import json, pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = 'static let shared = AppearanceModel()'
assert source.count(needle) == 1
replacement = ('static let shared = AppearanceModel(store: AppearanceStore(rootDirectory: '
    'URL(fileURLWithPath: ' + json.dumps(sys.argv[3]) + '), bundleIdentifier: "test.happylulu.panel-focus"), '
    'originalIcon: NSImage(size: NSSize(width: 16, height: 16)))')
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, replacement))
PY
# Offscreen CLI hosting exposes no AX button tree. Enter through the real beginEditing method;
# keep the panel body, focus observation, deferred save and click-away handling unchanged.
python3 - Sources/AfterSix/PanelView.swift "$probe_dir/PanelView.swift" <<'PY'
import pathlib, sys
source = pathlib.Path(sys.argv[1]).read_text()
needle = '.onAppear { model.refresh() }'
assert source.count(needle) == 1
pathlib.Path(sys.argv[2]).write_text(source.replace(needle, '.onAppear { model.refresh(); beginEditing() }'))
PY
swiftc -parse-as-library -swift-version 6 -I "$build_dir/Modules" \
  "$probe_dir/AppLanguage.swift" Sources/AfterSix/AppModel.swift \
  Sources/AfterSix/CalendarSyncModel.swift Sources/AfterSix/HalfDayCalendarReader.swift \
  Sources/AfterSix/DefaultFeatureAdapter.swift Sources/AfterSix/PluginManagerModel.swift \
  Sources/AfterSix/BundledPlugins.swift Sources/AfterSix/SettingsStyle.swift Sources/AfterSix/PluginSettingsView.swift \
  Sources/AfterSix/FeatureCalendarModel.swift Sources/AfterSix/TodayAgendaView.swift \
  Sources/AfterSix/TodayDayTypeView.swift Sources/AfterSix/ArrivalClockDigitField.swift Sources/AfterSix/LuluBrand.swift \
  Sources/AfterSix/LuluMaterials.swift Sources/AfterSix/MenuBarPanel.swift \
  "$probe_dir/PanelView.swift" "$probe_dir/AppearanceModel.swift" Tests/PanelFocusProbe/main.swift \
  "$build_dir"/AppPluginCore.build/*.swift.o "$build_dir"/AppPluginHost.build/*.swift.o \
  "$build_dir"/CPURunnerIntegration.build/*.swift.o \
  "$build_dir"/MacUtilitiesIntegration.build/*.swift.o \
  "$build_dir"/AfterSixCore.build/*.swift.o "$build_dir"/CalendarSyncServices.build/*.swift.o \
  "$build_dir"/CalendarSyncCore.build/*.swift.o \
  -framework AppKit -framework SwiftUI -framework Security -framework EventKit -framework ServiceManagement -lsqlite3 \
  -o "$probe_dir/panel-check"
for time_zone in UTC Asia/Seoul America/Los_Angeles; do
  case "$time_zone" in
    UTC) fixture_time_zone=Asia/Seoul ;;
    Asia/Seoul) fixture_time_zone=America/Los_Angeles ;;
    America/Los_Angeles) fixture_time_zone=UTC ;;
  esac
  TZ="$time_zone" "$probe_dir/panel-check" "$probe_dir/$time_zone" "$fixture_time_zone"
done
