#!/usr/bin/env bash
# Screenshots a built page in each of its backgrounds (four for the default template, light and dark for
# classic) and crops the top 2000px of each; for the default template also a phone shot (390px wide, the
# first 5700px laid out as three 1900px columns). Bounded rasters only.
# Usage: shoot.sh <out-dir> [height=8000]
set -euo pipefail
out=$(cd "$1" && pwd); hgt=${2:-8000}
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
themes="light lavender sand dark"; wide=1440; classic=
grep -q 'data-template="classic"' "$out/index.html" && { themes="light dark"; wide=1300; classic=1; }
for t in $themes; do
  "$CH" --headless=new --disable-gpu --hide-scrollbars --window-size=$wide,"$hgt" --screenshot="$out/shot-$t.png" "file://$out/index.html?theme=$t" 2>/dev/null
  sips -c 2000 $wide --cropOffset 1 0 "$out/shot-$t.png" --out "$out/top-$t.png" >/dev/null
done
if [ -z "$classic" ]; then
  # a 390px iframe is a real phone viewport (media queries apply); headless Chrome will not open a window that narrow
  { echo '<!doctype html><body style="margin:0;background:#000;display:flex;gap:10px">'
    for o in 0 1900 3800; do echo "<div style=\"width:390px;height:1900px;overflow:hidden\"><iframe src=\"index.html\" style=\"border:0;width:390px;height:6000px;margin-top:-${o}px\"></iframe></div>"; done
  } > "$out/phone-shot.html"
  "$CH" --headless=new --disable-gpu --hide-scrollbars --window-size=1190,1900 --screenshot="$out/top-phone.png" "file://$out/phone-shot.html" 2>/dev/null
  rm -f "$out/phone-shot.html"
fi
ls "$out"/top-*.png
