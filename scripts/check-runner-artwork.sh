#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${HAPPY_LULU_SKIP_BUILD:-0}" != "1" ]]; then
  swift build --build-system native --target CPURunnerIntegration >/dev/null
fi
build_dir="$(swift build --build-system native --show-bin-path)"
mkdir -p .build/runner-artwork
swiftc -parse-as-library -swift-version 6 \
  -module-cache-path "$PWD/.build/runner-artwork-modulecache" -I "$build_dir/Modules" \
  scripts/check-runner-artwork.swift \
  "$build_dir"/CPURunnerIntegration.build/*.swift.o \
  "$build_dir"/AppPluginCore.build/*.swift.o "$build_dir"/AppPluginHost.build/*.swift.o \
  -framework AppKit -framework SwiftUI -framework IOKit -framework SystemConfiguration \
  -o .build/runner-artwork/check
.build/runner-artwork/check "${1:-$PWD/.build/runner-artwork}"
