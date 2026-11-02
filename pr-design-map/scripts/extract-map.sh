#!/usr/bin/env bash
# Pulls map.json (or files.json) back out of a published single-file page, on disk, for the next run.
# Usage: extract-map.sh <index.html> [map|files] [out=map.json]
set -euo pipefail
page=$1; which=${2:-map}; out=${3:-$which.json}
sed -n "s|^<script type=\"application/json\" id=\"$which-json\">\(.*\)</script>\$|\1|p" "$page" | jq . > "$out"
[ -s "$out" ] || { echo "no $which-json block in $page" >&2; exit 1; }
echo "$out: $(wc -c < "$out" | tr -d ' ') bytes"
