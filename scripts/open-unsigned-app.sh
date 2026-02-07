#!/usr/bin/env bash
set -euo pipefail

app_path="${1:-/Applications/QatVasl.app}"

if [[ ! -d "$app_path" ]]; then
  echo "Error: app not found at: $app_path"
  echo "Usage: scripts/open-unsigned-app.sh [/path/to/QatVasl.app]"
  exit 1
fi

echo "Removing quarantine attribute from: $app_path"
xattr -dr com.apple.quarantine "$app_path"

echo "Opening app..."
open "$app_path"
