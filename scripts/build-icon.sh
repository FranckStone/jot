#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
resources="$project_dir/Resources"
iconset="$resources/AppIcon.iconset"
mkdir -p "$iconset"
rsvg-convert -w 1024 -h 1024 "$resources/icon.svg" -o "$resources/AppIcon.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$resources/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$resources/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"
python3 - "$resources" <<'PY'
import json
import pathlib
import sys

resources = pathlib.Path(sys.argv[1])
metadata = {
    "origin": "Authored dot-and-j monogram in Resources/icon.svg",
    "method": "scripts/build-icon.sh: rsvg-convert, sips, iconutil",
    "generated": False,
}
for asset in [resources / "AppIcon.png", resources / "AppIcon.icns", *sorted((resources / "AppIcon.iconset").glob("*.png"))]:
    pathlib.Path(str(asset) + ".json").write_text(json.dumps(metadata, indent=2) + "\n")
PY
printf 'Built %s\n' "$resources/AppIcon.icns"
