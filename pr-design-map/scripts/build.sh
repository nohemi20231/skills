#!/usr/bin/env bash
# Assembles ONE self-contained index.html: template shell + style.css (fonts as data: URIs) + map.json and
# files.json as JSON blocks + app.js. One file because claude.ai only opens multi-file artifacts in recent
# browsers (older Safari shows "This browser isn't supported"). Everything happens on disk.
# Usage: build.sh [-t <template>] <out-dir> <files.json> <map.json>
# The template is template/ (the default look) or template-<name>/ (for example classic); -t wins over map.json's "template".
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
tpl=
while getopts t: opt; do case $opt in t) tpl=$OPTARG;; *) exit 2;; esac; done; shift $((OPTIND - 1))
out=$1; files=$2; map=$3
mkdir -p "$out"
[ -n "$tpl" ] || tpl=$(jq -r '.template // "default"' "$map")
case $tpl in default|"") tdir=$here/template;; *) tdir=$here/template-$tpl;; esac
[ -f "$tdir/index.html" ] || { echo "no template '$tpl' ($tdir)" >&2; exit 1; }

merged=$(jq -s '.[0] * .[1]' "$files" "$map")
jq -e '.app and .pr.number and .pr.head and .pr.owner and .pr.repo and (.sections|length>0) and (.files|length>0)' <<<"$merged" >/dev/null \
  || { echo "merged data is missing app, pr.{number,head,owner,repo}, sections or files" >&2; exit 1; }

# JSON inside <script>: every "<" becomes <, so no "</script>" or "<!--" can end the block early.
json_block() { printf '<script type="application/json" id="%s">' "$1"; jq -c . "$2" | sed 's/</\\u003c/g' | tr -d '\n'; printf '</script>\n'; }

style() {
  printf '<style>\n'
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ $line =~ url\(fonts/([a-z0-9-]+\.woff2)\) ]]; then
      font=${BASH_REMATCH[1]}
      b64=$(base64 < "$tdir/fonts/$font" | tr -d '\n')
      pat="url(fonts/$font)"; rep="url(data:font/woff2;base64,$b64)"
      line=${line//"$pat"/$rep}
    fi
    printf '%s\n' "$line"
  done < "$tdir/style.css"
  printf '</style>'
}

# A caption under every diagram: one or two sentences, 30 words at most. Reported, never fatal, so an older map still builds.
# A caption that is not a string counts as missing (the page does not show it either).
jq -r '.sections[] | select(.type == "sequence" or .type == "modules" or .type == "hub" or .type == "tree" or .type == "lifecycle")
  | (.caption | if type == "string" then . else "" end | split("\n") | join(" ") | split("\t") | join(" ") | split(" ") | map(select(length > 0)) | length) as $words
  | if $words == 0 then "warning: section \"\(.title)\" has no caption"
    elif $words > 30 then "warning: the caption of \"\(.title)\" has \($words) words (30 at most)" else empty end' <<<"$merged" >&2

title=$(jq -r '"\(.app) Design Map: PR #\(.pr.number)" | @html' <<<"$merged")
while IFS= read -r line || [ -n "$line" ]; do
  case $line in
    @@STYLE@@) style; echo ;;
    @@DATA@@) json_block files-json "$files"; json_block map-json "$map" ;;
    @@APP@@) printf '<script>\n'; cat "$tdir/app.js"; printf '</script>\n' ;;
    *) printf '%s\n' "${line//@@TITLE@@/$title}" ;;
  esac
done < "$tdir/index.html" > "$out/index.html"

# Kept beside the page for the next run's scope check; only index.html is published.
cp "$map" "$out/map.json"; cp "$files" "$out/files.json"
echo "built $out/index.html ($(wc -c < "$out/index.html" | tr -d ' ') bytes, template $tpl): $(jq -r '"\(.app) PR #\(.pr.number) · \(.files|length) files · \(.sections|length) sections"' <<<"$merged")"
