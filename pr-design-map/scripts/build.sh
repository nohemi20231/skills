#!/usr/bin/env bash
# Assembles a publishable page: template + fonts + data.js (files.json merged with map.json).
# Usage: build.sh <out-dir> <files.json> <map.json>
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=$1; files=$2; map=$3
mkdir -p "$out/fonts"
cp "$here/template/index.html" "$here/template/style.css" "$here/template/app.js" "$out/"
cp "$here/template/fonts/"*.woff2 "$out/fonts/"
cp "$map" "$out/map.json"; cp "$files" "$out/files.json"
merged=$(jq -s '.[0] * .[1]' "$files" "$map")
jq -e '.app and .pr.number and .pr.head and .pr.owner and .pr.repo and (.sections|length>0) and (.files|length>0)' <<<"$merged" >/dev/null \
  || { echo "merged data is missing app, pr.{number,head,owner,repo}, sections or files" >&2; exit 1; }
printf 'window.MAP = %s;\n' "$merged" > "$out/data.js"
echo "built $out: $(jq -r '"\(.app) PR #\(.pr.number) · \(.files|length) files · \(.sections|length) sections"' <<<"$merged")"
