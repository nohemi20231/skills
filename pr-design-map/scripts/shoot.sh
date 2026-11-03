#!/usr/bin/env bash
# Screenshots a built page in each of its backgrounds (three for the default template, light and dark for
# classic) and crops the top 2000px of each. Bounded rasters only.
# Usage: shoot.sh <out-dir> [height=8000]
set -euo pipefail
out=$(cd "$1" && pwd); hgt=${2:-8000}
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
themes="light sand dark"; grep -q 'data-template="classic"' "$out/index.html" && themes="light dark"
for t in $themes; do
  "$CH" --headless=new --disable-gpu --hide-scrollbars --window-size=1300,"$hgt" --screenshot="$out/shot-$t.png" "file://$out/index.html?theme=$t" 2>/dev/null
  sips -c 2000 1300 --cropOffset 1 0 "$out/shot-$t.png" --out "$out/top-$t.png" >/dev/null
done
ls "$out"/top-*.png
