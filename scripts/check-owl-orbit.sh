#!/bin/bash
# Native renderer checks; use the existing debug modules without starting SwiftPM.
set -euo pipefail
cd "$(dirname "$0")/.."
build_dir="${HAPPY_LULU_BUILD_DIR:-$PWD/.build/debug}"
check_dir="$PWD/.build/owl-orbit"
if [[ ! -d "$build_dir/Modules" ]]; then
  echo "Build debug modules first or set HAPPY_LULU_BUILD_DIR to their directory." >&2
  exit 1
fi
mkdir -p "$check_dir"
output="${1:-$check_dir/evidence}"
if [[ -e "$output/owl-orbit-comparison.png" ]]; then
  archive="$output/validation-history/render-$(date '+%Y%m%d-%H%M%S')-$$"
  mkdir -p "$archive"
  for artifact in frames-light frames-dark frames-custom-light frames-custom-dark owl-colors-comparison.png owl-orbit-comparison.png owl-orbit-speed-comparison.gif owl-orbit-checks.txt; do
    if [[ -e "$output/$artifact" ]]; then mv "$output/$artifact" "$archive/"; fi
  done
fi
mkdir -p "$output"
swiftc -swift-version 6 -whole-module-optimization -emit-object -emit-module -module-name AppPluginHost \
  -module-cache-path "$check_dir/module-cache" -I "$build_dir/Modules" \
  Sources/AppPluginHost/*.swift -emit-module-path "$check_dir/AppPluginHost.swiftmodule" -o "$check_dir/AppPluginHost.o"
swiftc -parse-as-library -swift-version 6 -module-cache-path "$check_dir/module-cache" \
  -I "$check_dir" -I "$build_dir/Modules" Sources/AfterSix/LuluBrand.swift scripts/check-owl-orbit.swift \
  "$check_dir/AppPluginHost.o" "$build_dir"/AppPluginCore.build/*.swift.o "$build_dir"/AfterSixCore.build/*.swift.o \
  -framework AppKit -framework SwiftUI -framework ImageIO -o "$check_dir/check"
"$check_dir/check" "$output" | tee "$output/owl-orbit-checks.txt"
