#!/bin/bash
# Regenerate Resources/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p Resources build
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
rm -rf build/AppIcon.iconset
echo "Wrote Resources/AppIcon.icns"
