#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${HAPPY_LULU_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --disable-sandbox --build-system native --product HappyLulu >/dev/null
fi
build_dir="$(swift build --disable-sandbox --build-system native --show-bin-path)"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp/}HappyLulu-codex-symbol.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
swiftc -parse-as-library -swift-version 6 -module-cache-path "$PWD/.build/codex-symbol-module-cache" \
  -I "$build_dir/Modules" Sources/AIUsageIntegration/CodexMenuBarIcon.swift scripts/check-codex-symbol.swift \
  "$build_dir"/AppPluginCore.build/*.swift.o "$build_dir"/AppPluginHost.build/*.swift.o \
  "$build_dir"/AIUsagePlugin.build/*.swift.o "$build_dir"/AIUsageIntegration.build/*.swift.o \
  -framework AppKit -framework SwiftUI -framework UserNotifications -framework Security \
  -o "$probe_dir/check"
"$probe_dir/check"
