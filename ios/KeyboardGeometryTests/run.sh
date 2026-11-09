#!/bin/sh
# Compiles and runs the keyboard geometry checks. No simulator needed.
set -e

dir=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$dir/../.." && pwd)

swiftc -o "$dir/.geometry-tests" \
  "$dir/main.swift" \
  "$root/ios/cupertino_interactive_keyboard/Sources/cupertino_interactive_keyboard/KeyboardGeometry.swift"

"$dir/.geometry-tests"
rm -f "$dir/.geometry-tests"
