#!/bin/zsh
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift and the shared mark geometry.
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swiftc -parse-as-library -o "$WORK/make-icon" scripts/make-icon.swift Sources/GitOS/Views/GitOSMarkGeometry.swift
"$WORK/make-icon" "$WORK/AppIcon.iconset"
iconutil -c icns -o Resources/AppIcon.icns "$WORK/AppIcon.iconset"
echo "Wrote Resources/AppIcon.icns"
