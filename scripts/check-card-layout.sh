#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_file="$(mktemp /tmp/jot-card-layout.XXXXXX.swift)"
trap 'rm -f "$probe_file"' EXIT
# Compile the UI component with its real dependencies, without launching main.swift.
cat Sources/JotCore/*.swift Sources/Jot/Components.swift Sources/Jot/FindReplaceBar.swift Sources/Jot/WorkbenchViews.swift Tests/AppKit/CardLayoutProbe.swift | sed '/^import JotCore$/d' > "$probe_file"
swift "$probe_file"
