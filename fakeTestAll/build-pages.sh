#!/usr/bin/env bash
# Builds the design map of each mocked PR in both designs under out/, writes the local stand-in for GitHub to
# out/mock-github, and points the pages' GitHub links at it (mock-links.js). Needs git and jq; no browser.
# Usage: build-pages.sh
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
case $here in */fakeTestAll) ;; *) echo "expected to live in fakeTestAll, not $here" >&2; exit 1;; esac
skill=$(cd "$here/../pr-design-map" && pwd)
out=$here/out
[ -d "$here/repo/.git" ] || "$here/make-fake-repo.sh"
rm -rf "$out"; mkdir -p "$out"

# add_links <built page> <files.json> <map.json>: mock-links.js goes in just before </body>
add_links() {
  local n gh session
  n=$(wc -l < "$1" | tr -d ' ')
  [ "$(tail -n 2 "$1" | tr -d '\n')" = "</body></html>" ] || { echo "$1 does not end with </body></html>" >&2; exit 1; }
  gh=$(jq -r '"https://github.com/\(.pr.owner)/\(.pr.repo)/"' "$2"); session=$(jq -r '.session.url // ""' "$3")
  { head -n $((n - 2)) "$1"
    echo '<script>'; sed -e "s|@GH@|$gh|" -e "s|@SESSION@|$session|" "$here/mock-links.js"; echo '</script>'
    printf '</body>\n</html>\n'
  } > "$1.tmp"
  mv "$1.tmp" "$1"
}

echo "build"
for n in 7 8; do
  files=$here/prs/pr-$n/files.json; map=$here/prs/pr-$n/map.json
  "$here/mock-github.sh" "$here/repo" "$files" "pr-$n-base" "$out/mock-github" >/dev/null
  echo "  out/mock-github/pull-$n.html"
  for t in default classic; do
    "$skill/scripts/build.sh" -t "$t" "$out/pr-$n-$t" "$files" "$map" >/dev/null
    add_links "$out/pr-$n-$t/index.html" "$files" "$map"
    echo "  out/pr-$n-$t/index.html"
  done
done
