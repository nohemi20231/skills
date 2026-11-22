#!/usr/bin/env bash
# Builds the design map of each mocked PR in both designs (build-pages.sh), then shoots every design, theme and
# option into screenshots/ and writes gallery.html and overview.png. Needs Google Chrome, git and jq (macOS).
# Usage: shoot-all.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
case $here in */fakeTestAll) ;; *) echo "expected to live in fakeTestAll, not $here" >&2; exit 1;; esac
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
out=$here/out; shots=$here/screenshots; var=$out/_variants
"$here/build-pages.sh"
rm -rf "$shots"; mkdir -p "$shots" "$var"
prof=$(mktemp -d "${TMPDIR:-/tmp}/dm-chrome.XXXXXX"); trap 'rm -rf "$prof"' EXIT
: > "$out/gallery.tsv"

chrome() { "$CH" --headless=new --disable-gpu --hide-scrollbars --no-first-run --user-data-dir="$prof" "$@" 2>/dev/null; }

# one gallery row: entry <group> <label> <png>
entry() { printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$out/gallery.tsv"; }

# The top of a page: shot <group> <label> <png> <width> <height> <url>
shot() {
  chrome --window-size="$4,$5" --screenshot="$shots/$3" "$6" >/dev/null
  [ -s "$shots/$3" ] || { echo "no screenshot for $3" >&2; exit 1; }
  entry "$1" "$2" "$3"; echo "  $3"
}

# A copy of a built page that runs <js> once it has rendered (a click on Settings, opening a fold).
# Screenshot-only: the pages under out/ and the templates are never changed.
# inject <page-file> <new-file> <js>
inject() {
  local n; n=$(wc -l < "$1" | tr -d ' ')
  { head -n $((n - 2)) "$1"; printf '<script>addEventListener("load", function () { %s });</script>\n</body>\n</html>\n' "$3"; } > "$2"
}

# probe <page-file> <query> <width> [selector]: prints "<page height> <top of the selector>"
probe() {
  inject "$1" "$var/_probe.html" "var d = document.documentElement, e = document.querySelector('${4:-html}'); d.setAttribute('data-h', d.scrollHeight); d.setAttribute('data-top', Math.round(e.getBoundingClientRect().top + scrollY));"
  chrome --window-size="$3,1000" --dump-dom "file://$var/_probe.html?$2" | sed -n 's/.*data-h="\([0-9]*\)" data-top="\([0-9]*\)".*/\1 \2/p' | head -1
}

# A window onto a page, <offset> px down. Headless Chrome shoots only the top of a document and no more than
# 16000px, so the page sits in a full-height iframe that a clipping box moves up.
# region <group> <label> <png> <width> <height> <page-file> <query> <offset> <page-height>
region() {
  mkdir -p "$(dirname "$shots/$3")"
  printf '<!doctype html><body style="margin:0;overflow:hidden"><div style="width:%spx;height:%spx;overflow:hidden"><iframe src="file://%s?%s" style="border:0;display:block;width:%spx;height:%spx;margin-top:-%spx"></iframe></div>\n' \
    "$4" "$5" "$6" "$7" "$4" "$9" "$8" > "$var/_region.html"
  chrome --window-size="$4,$5" --screenshot="$shots/$3" "file://$var/_region.html" >/dev/null
  [ -s "$shots/$3" ] || { echo "no screenshot for $3" >&2; exit 1; }
  entry "$1" "$2" "$3"
}

# One part of a page, starting just above an element.
# at <group> <label> <png> <width> <height> <page-file> <query> <selector>
at() {
  local h top tall=$5
  read -r h top < <(probe "$6" "$7" "$4" "$8")
  [ -n "${h:-}" ] || { echo "could not find $8 in $6" >&2; exit 1; }
  top=$((top > 24 ? top - 24 : 0))
  # stop at the end of the page instead of shooting empty background
  [ $((top + tall)) -le "$h" ] || tall=$((h - top))
  region "$1" "$2" "$3" "$4" "$tall" "$6" "$7" "$top" "$h"; echo "  $3"
}

# The whole page as 2000px parts.
# full <group> <label> <dir> <width> <page-file> <query>
full() {
  local h _ off=0 i=1 ph
  read -r h _ < <(probe "$5" "$6" "$4")
  [ -n "${h:-}" ] || { echo "could not measure $5" >&2; exit 1; }
  while [ "$off" -lt "$h" ]; do
    ph=$((h - off)); [ "$ph" -le 2000 ] || ph=2000
    # a last sliver is only the page's bottom padding
    [ "$ph" -ge 300 ] || [ "$i" -eq 1 ] || break
    region "$1" "$2 · part $i" "$(printf '%s/part-%02d.png' "$3" "$i")" "$4" "$ph" "$5" "$6" "$off" "$h"
    off=$((off + 2000)); i=$((i + 1))
  done
  echo "  $3/ ($((i - 1)) parts, ${h}px)"
}

d7=$out/pr-7-default/index.html; c7=$out/pr-7-classic/index.html
d8=$out/pr-8-default/index.html; c8=$out/pr-8-classic/index.html
slate='theme=slate&json=cell'

echo "designs"
G="1 · The two designs (mocked PR #7)"
shot "$G" "Default design" design-default.png 1440 2000 "file://$d7?$slate"
shot "$G" "Classic design" design-classic.png 1300 2000 "file://$c7?theme=light"

echo "themes"
G="2 · Themes of the default design"
for t in slate lavender sand dark; do shot "$G" "Background: $t" "default-theme-$t.png" 1440 1300 "file://$d7?theme=$t&json=cell"; done
G="3 · Themes of the classic design"
for t in light dark; do shot "$G" "Theme: $t" "classic-theme-$t.png" 1300 1300 "file://$c7?theme=$t"; done

echo "options"
G="4 · Options of the default design"
inject "$d7" "$var/settings.html" 'document.querySelector("button[aria-controls=sheet-settings]").click();'
shot "$G" "Settings panel (⚙)" option-settings-panel.png 1440 1000 "file://$var/settings.html?$slate"
inject "$d7" "$var/key.html" 'document.querySelector("button[aria-controls=sheet-key]").click();'
shot "$G" "Key panel" option-key-panel.png 1440 1500 "file://$var/key.html?$slate"
at "$G" "JSON tiles: Cell type" option-json-cell.png 1440 1000 "$d7" "$slate" '#the-json'
at "$G" "JSON tiles: Classic" option-json-classic.png 1440 1000 "$d7" 'theme=slate&json=classic' '#the-json'
inject "$d7" "$var/folds.html" 'var b = document.querySelectorAll(".fold-btn[aria-expanded=true]"); b[0].click(); b[1].click();'
shot "$G" "Folds closed: What changed and the diagram (Show ▾)" option-folds-closed.png 1440 1000 "file://$var/folds.html?$slate"
inject "$d7" "$var/lists.html" 'document.querySelectorAll(".fold.files > .fold-btn").forEach(function (b) { b.click(); });'
at "$G" "Tests and Other files opened (folded at first)" option-tests-other-open.png 1440 1400 "$var/lists.html" "$slate" '.fold.files'
shot "$G" "Top bar layout (under 1400px wide)" option-layout-topbar.png 1100 1300 "file://$d7?$slate"
# a 390px iframe is a real phone viewport; headless Chrome will not open a window that narrow
{ echo '<!doctype html><body style="margin:0;background:#000;display:flex;gap:10px">'
  for o in 0 1900 3800; do echo "<div style=\"width:390px;height:1900px;overflow:hidden\"><iframe src=\"file://$d7?$slate\" style=\"border:0;width:390px;height:6000px;margin-top:-${o}px\"></iframe></div>"; done
} > "$var/phone.html"
shot "$G" "Phone, 390px wide (first 5700px as three columns)" option-phone.png 1190 1900 "file://$var/phone.html"

echo "proposal"
G="5 · A design proposal (mocked PR #8)"
at "$G" "Default design" proposal-default.png 1440 2000 "$d8" "$slate" '#proposed-changes'
at "$G" "Classic design" proposal-classic.png 1300 2000 "$c8" 'theme=light' '#proposed-changes'

echo "full pages"
full "6 · Whole page: mocked PR #7, default design" "PR #7 default" pr-7-default 1440 "$d7" "$slate"
full "7 · Whole page: mocked PR #7, classic design" "PR #7 classic" pr-7-classic 1300 "$c7" 'theme=light'
full "8 · Whole page: mocked PR #8, default design" "PR #8 default" pr-8-default 1440 "$d8" "$slate"
full "9 · Whole page: mocked PR #8, classic design" "PR #8 classic" pr-8-classic 1300 "$c8" 'theme=light'

echo "gallery"
{
  cat <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>fakeTestAll: design map samples</title>
<style>
  body { margin: 0; padding: 28px 32px 60px; background: #d5dae3; color: #1a1f2b; font: 18px/1.6 Lexend, "Avenir Next", Verdana, sans-serif; letter-spacing: .02em; }
  h1 { font-size: 30px; margin: 0 0 4px; }
  p.sub { margin: 0 0 8px; color: #485061; }
  h2 { font-size: 23px; margin: 44px 0 14px; padding-top: 14px; border-top: 1px solid #bfc6d3; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(420px, 1fr)); gap: 18px; align-items: start; }
  a.tile { display: block; background: #e6e9ef; border: 1px solid #bfc6d3; border-radius: 10px; overflow: hidden; color: inherit; text-decoration: none; }
  a.tile b { display: block; padding: 10px 14px; font-size: 17px; border-bottom: 1px solid #bfc6d3; }
  a.tile img { display: block; width: 100%; height: auto; }
</style>
</head>
<body>
<h1>Design map samples</h1>
<p class="sub">Fake app "Corner Bakery", two mocked pull requests. Click a picture to open it at full size.</p>
EOF
  awk -F'\t' '
    $1 != g { if (g != "") print "</div>"; g = $1; printf "<h2>%s</h2>\n<div class=\"grid\">\n", g }
    { printf "<a class=\"tile\" href=\"screenshots/%s\"><b>%s</b><img loading=\"lazy\" src=\"screenshots/%s\" alt=\"%s\"></a>\n", $3, $2, $3, $2 }
    END { if (g != "") print "</div>" }' "$out/gallery.tsv"
  printf '</body>\n</html>\n'
} > "$here/gallery.html"

# overview.png: groups 1 to 5 (designs, themes, options, proposal) on one sheet
{ awk '/<h2>6 · /{exit} {print}' "$here/gallery.html" | sed 's/loading="lazy" //'
  printf '<script>addEventListener("load", function () { document.documentElement.setAttribute("data-h", document.documentElement.scrollHeight); });</script>\n</body>\n</html>\n'
} > "$here/_overview.html"
oh=$(chrome --window-size=1900,1000 --dump-dom "file://$here/_overview.html" | sed -n 's/.*data-h="\([0-9]*\)".*/\1/p' | head -1)
[ "${oh:-6000}" -le 16000 ] || oh=16000
chrome --window-size="1900,${oh:-6000}" --screenshot="$here/overview.png" "file://$here/_overview.html" >/dev/null
rm -f "$here/_overview.html"; rm -rf "$var"

echo "done: $(find "$shots" -name '*.png' | wc -l | tr -d ' ') screenshots, $(du -sh "$shots" | cut -f1 | tr -d ' ')"
echo "  $here/gallery.html"
echo "  $here/overview.png"
