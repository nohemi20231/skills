#!/usr/bin/env bash
# Mocked pull request: writes the same files.json as pr-design-map/scripts/pr-files.sh, but from two refs
# of a local repo instead of a GitHub PR read with gh. The owner, repo and PR URL are made up
# (example/corner-bakery); the head commit, statuses, line counts and diff anchors come from git.
# Usage: mock-pr-files.sh <repo-dir> <pr-number> <base-ref> <head-branch> [out=files.json]
set -euo pipefail
dir=$1; pr=$2; base=$3; branch=$4; out=${5:-files.json}
out=$(cd "$(dirname "$out")" && pwd)/$(basename "$out")
cd "$dir"
owner=example; repo=corner-bakery
head=$(git rev-parse "$branch^{commit}")
from=$(git merge-base "$base" "$head")
date=$(git show -s --format=%cs "$head")
{
  jq -n --argjson n "$pr" --arg owner "$owner" --arg repo "$repo" --arg branch "$branch" --arg head "$head" --arg date "$date" \
    '{pr: {number: $n, url: "https://github.com/\($owner)/\($repo)/pull/\($n)", owner: $owner, repo: $repo, branch: $branch, head: $head, base: "main", date: $date}}'
  echo '{"files":['
  first=1
  while IFS=$'\t' read -r st path; do
    [ -n "$path" ] || continue
    case $st in A) status=added;; D) status=deleted;; *) status=modified;; esac
    read -r add del _ < <(git diff --numstat --no-renames "$from" "$head" -- "$path")
    if [ "$status" = deleted ]; then lines=0; else lines=$(git show "$head:$path" | wc -l | tr -d ' '); fi
    anchor=$(printf '%s' "$path" | shasum -a 256 | cut -d' ' -f1)
    [ $first = 1 ] || echo ','; first=0
    jq -nc --arg p "$path" --arg s "$status" --argjson a "$add" --argjson d "$del" --argjson l "$lines" --arg h "$anchor" \
      '{path:$p,status:$s,added:$a,removed:$d,lines:$l,anchor:$h}'
  done < <(git diff --name-status --no-renames "$from" "$head")
  echo ']}'
} | jq -s '.[0] * .[1]' > "$out"
echo "$out: PR #$pr, $(jq '.files|length' "$out") files, head $(printf '%s' "$head" | cut -c1-7)"
