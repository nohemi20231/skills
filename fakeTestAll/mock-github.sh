#!/usr/bin/env bash
# Local stand-in for the GitHub pages of a mocked pull request, so the links of its design map open something:
#   <out>/pull-<n>.html              the pull request: commits and changed files
#   <out>/pull-<n>-files.html        the "Files changed" tab, one diff per file at #diff-<anchor>
#   <out>/blob/<head>/<path>.html    each changed file at the head commit, one row per line at #L<line>
#   <out>/session.html               where the Session link goes
# Everything comes from git and from the files.json that mock-pr-files.sh wrote. Needs git and jq.
# Usage: mock-github.sh <repo-dir> <files.json> <base-ref> <out-dir>
set -euo pipefail
repo=$(cd "$1" && pwd); files=$(cd "$(dirname "$2")" && pwd)/$(basename "$2"); base=$3
mkdir -p "$4"; out=$(cd "$4" && pwd)
n=$(jq -r .pr.number "$files"); head=$(jq -r .pr.head "$files"); branch=$(jq -r .pr.branch "$files")
slug=$(jq -r '"\(.pr.owner)/\(.pr.repo)"' "$files"); date=$(jq -r .pr.date "$files")
git -C "$repo" cat-file -e "$head^{commit}" 2>/dev/null \
  || { echo "$head is not in $repo: run make-fake-repo.sh, then mock-pr-files.sh" >&2; exit 1; }
from=$(git -C "$repo" merge-base "$base" "$head")
short=$(printf '%s' "$head" | cut -c1-7)

esc() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }
title=$(git -C "$repo" show -s --format=%s "$head" | esc)
count=$(jq '.files | length' "$files"); added=$(jq '[.files[].added] | add' "$files"); removed=$(jq '[.files[].removed] | add' "$files")

css=$(cat <<'EOF'
body { margin: 0; padding: 24px 32px 80px; background: #d5dae3; color: #1a1f2b; font: 18px/1.6 Lexend, "Avenir Next", Verdana, sans-serif; letter-spacing: .02em; }
a { color: #1d4f91; }
.mock { margin: 0 0 22px; padding: 10px 16px; background: #fbe9b7; border: 1px solid #c9a227; border-radius: 10px; }
h1 { font-size: 28px; line-height: 1.3; margin: 0 0 6px; overflow-wrap: anywhere; }
h1 span { color: #5a6375; font-weight: 400; }
h2 { font-size: 21px; margin: 0; }
.meta { margin: 0 0 18px; color: #485061; }
.tabs { display: flex; gap: 8px; margin: 0 0 22px; border-bottom: 1px solid #bfc6d3; }
.tabs a, .tabs b { padding: 8px 16px; border: 1px solid #bfc6d3; border-bottom: 0; border-radius: 10px 10px 0 0; background: #e6e9ef; text-decoration: none; }
.tabs b { background: #f4f6f9; }
.box { background: #f4f6f9; border: 1px solid #bfc6d3; border-radius: 10px; margin: 0 0 22px; overflow: hidden; }
.box > header { display: flex; flex-wrap: wrap; gap: 6px 14px; align-items: baseline; padding: 10px 16px; background: #e6e9ef; border-bottom: 1px solid #bfc6d3; }
.box:target { outline: 4px solid #c9a227; }
.path { font: 600 16px/1.5 ui-monospace, Menlo, monospace; letter-spacing: 0; overflow-wrap: anywhere; }
h1.path { font-size: 22px; }
.st { padding: 1px 10px; border-radius: 999px; font-size: 15px; border: 1px solid; white-space: nowrap; }
.st.added { background: #d9f0dd; border-color: #6aa977; }
.st.modified { background: #dbe7f8; border-color: #7a9fd0; }
.st.deleted { background: #f8dcdc; border-color: #cf8a8a; }
.plus { color: #1c6b2f; font-weight: 600; }
.minus { color: #a12a2a; font-weight: 600; }
.right { margin-left: auto; white-space: nowrap; }
table { border-collapse: collapse; width: 100%; }
table.code { font: 15px/1.55 ui-monospace, Menlo, monospace; letter-spacing: 0; }
table.code td { padding: 0 10px; vertical-align: top; }
td.n { width: 1%; text-align: right; color: #6b7385; user-select: none; white-space: nowrap; }
td.c { white-space: pre-wrap; overflow-wrap: anywhere; }
tr.add { background: #dcf3e0; }
tr.del { background: #f9dede; }
tr.hunk { background: #e2e8f3; color: #485061; }
tr:target { background: #fbe9b7; }
table.list td { padding: 8px 16px; border-top: 1px solid #d5dae3; }
table.list tr:first-child td { border-top: 0; }
ul.commits { margin: 0; padding: 10px 16px 10px 40px; }
EOF
)

# top <page title, already escaped>
top() {
  cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$1</title>
<style>
$css
</style>
</head>
<body>
<p class="mock"><b>Mocked page.</b> It stands in for github.com/$slug, which does not exist, and is built from the local repo in fakeTestAll/repo.</p>
EOF
}
bottom() { printf '</body>\n</html>\n'; }
delta() { printf '<span class="plus">+%s</span> <span class="minus">−%s</span>' "$1" "$2"; }
# heading <"" or "../../" back to the out dir>: the title, the facts line and the two tabs' targets
heading() {
  printf '<h1>%s <span>#%s</span></h1>\n' "$title" "$n"
  printf '<p class="meta">%s → main · %s · %s · %s files %s</p>\n' "$branch" "$short" "$date" "$count" "$(delta "$added" "$removed")"
}
rows() { jq -r '.files[] | [.path, .status, .added, .removed, .anchor] | @tsv' "$files"; }

# the pull request
{
  top "$title · Pull request #$n"
  heading
  printf '<nav class="tabs"><b>Pull request</b><a href="pull-%s-files.html">Files changed (%s)</a></nav>\n' "$n" "$count"
  printf '<section class="box"><header><h2>Commits</h2></header>\n<ul class="commits">\n'
  git -C "$repo" log --reverse --format='%h%x09%s' "$from..$head" | esc | while IFS=$'\t' read -r sha subject; do
    printf '<li><span class="path">%s</span> %s</li>\n' "$sha" "$subject"
  done
  printf '</ul>\n</section>\n<section class="box"><header><h2>Changed files</h2></header>\n<table class="list">\n'
  rows | while IFS=$'\t' read -r path status add del anchor; do
    printf '<tr><td class="n"><span class="st %s">%s</span></td><td><a class="path" href="pull-%s-files.html#diff-%s">%s</a></td><td class="n">%s</td><td class="n"><a href="blob/%s/%s.html">View file</a></td></tr>\n' \
      "$status" "$status" "$n" "$anchor" "$path" "$(delta "$add" "$del")" "$head" "$path"
  done
  printf '</table>\n</section>\n'
  bottom
} > "$out/pull-$n.html"

# the "Files changed" tab
{
  top "Files changed · Pull request #$n"
  heading
  printf '<nav class="tabs"><a href="pull-%s.html">Pull request</a><b>Files changed (%s)</b></nav>\n' "$n" "$count"
  rows | while IFS=$'\t' read -r path status add del anchor; do
    printf '<section class="box" id="diff-%s"><header><span class="st %s">%s</span><span class="path">%s</span><span class="right">%s · <a href="blob/%s/%s.html">View file</a></span></header>\n<table class="code">\n' \
      "$anchor" "$status" "$status" "$path" "$(delta "$add" "$del")" "$head" "$path"
    git -C "$repo" diff --no-renames --no-color -U3 "$from" "$head" -- "$path" | awk '
      function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
      /^@@/ {
        match($0, /-[0-9]+/); o = substr($0, RSTART + 1, RLENGTH - 1) + 0
        match($0, /\+[0-9]+/); n = substr($0, RSTART + 1, RLENGTH - 1) + 0
        inside = 1
        printf "<tr class=\"hunk\"><td class=\"n\"></td><td class=\"n\"></td><td class=\"c\">%s</td></tr>\n", esc($0); next
      }
      !inside || /^\\/ { next }
      { sign = substr($0, 1, 1); text = esc(substr($0, 2)) }
      sign == "+" { printf "<tr class=\"add\"><td class=\"n\"></td><td class=\"n\">%d</td><td class=\"c\">+ %s</td></tr>\n", n++, text; next }
      sign == "-" { printf "<tr class=\"del\"><td class=\"n\">%d</td><td class=\"n\"></td><td class=\"c\">- %s</td></tr>\n", o++, text; next }
      { printf "<tr><td class=\"n\">%d</td><td class=\"n\">%d</td><td class=\"c\">  %s</td></tr>\n", o++, n++, text }'
    printf '</table>\n</section>\n'
  done
  bottom
} > "$out/pull-$n-files.html"

# each changed file at the head commit
rows | while IFS=$'\t' read -r path status add del anchor; do
  page=$out/blob/$head/$path.html; mkdir -p "$(dirname "$page")"
  slashes=${path//[^\/]/}; up=../../; for ((i = 0; i < ${#slashes}; i++)); do up=../$up; done
  {
    top "$path at $short"
    printf '<h1 class="path">%s</h1>\n' "$path"
    printf '<p class="meta"><span class="st %s">%s</span> in <a href="%spull-%s.html">pull request #%s</a> · at %s · <a href="%spull-%s-files.html#diff-%s">View changes</a> %s</p>\n' \
      "$status" "$status" "$up" "$n" "$n" "$short" "$up" "$n" "$anchor" "$(delta "$add" "$del")"
    if [ "$status" = deleted ]; then
      printf '<section class="box"><header>This pull request deletes the file, so there is nothing to show at %s.</header></section>\n' "$short"
    else
      printf '<section class="box">\n<table class="code">\n'
      git -C "$repo" show "$head:$path" | awk '
        function esc(s) { gsub(/&/, "\\&amp;", s); gsub(/</, "\\&lt;", s); gsub(/>/, "\\&gt;", s); return s }
        { printf "<tr id=\"L%d\"><td class=\"n\">%d</td><td class=\"c\">%s</td></tr>\n", NR, NR, esc($0) }'
      printf '</table>\n</section>\n'
    fi
    bottom
  } > "$page"
done

# where the Session link goes
{
  top "Mocked session"
  printf '<h1>Mocked session</h1>\n'
  printf '<p class="meta">On a real design map this link opens the Claude Code session that wrote the pull request. The mocked pull requests were written by make-fake-repo.sh, so there is no session to open.</p>\n'
  bottom
} > "$out/session.html"

echo "$out: PR #$n, $count files at $short"
