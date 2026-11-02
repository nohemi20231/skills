#!/usr/bin/env bash
# Writes files.json for a PR: PR facts plus, per changed file, status, lines added/removed (from the PR's
# files list), total lines at the head commit and the SHA-256 diff anchor (from git). Nothing is estimated.
# Usage: pr-files.sh <repo-dir> <pr-number> [out=files.json]
# Needs: gh (authenticated), jq, shasum, git with the head commit fetched (the script fetches it).
set -euo pipefail
dir=$1; pr=$2; out=${3:-files.json}
cd "$dir"
nwo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
owner=${nwo%/*}; repo=${nwo#*/}
meta=$(gh pr view "$pr" --json number,url,headRefName,headRefOid,baseRefName,createdAt)
head=$(jq -r '.headRefOid' <<<"$meta")
git cat-file -e "$head^{commit}" 2>/dev/null || git fetch -q origin "refs/pull/$pr/head" || git fetch -q origin "$head"
list=$(gh api --paginate "repos/$nwo/pulls/$pr/files" -q '.[] | [.filename, .status, .additions, .deletions, (.previous_filename // "")] | @tsv')
{
  jq --arg owner "$owner" --arg repo "$repo" '{pr: {number, url, owner: $owner, repo: $repo, branch: .headRefName, head: .headRefOid, base: .baseRefName, date: (.createdAt|split("T")[0])}}' <<<"$meta"
  echo '{"files":['
  first=1
  while IFS=$'\t' read -r path status add del prev; do
    [ -n "$path" ] || continue
    case $status in added|modified|removed|renamed) ;; *) status=modified;; esac
    [ "$status" = removed ] && status=deleted
    if [ "$status" = deleted ]; then lines=0; else lines=$(git show "$head:$path" | wc -l | tr -d ' '); fi
    anchor=$(printf '%s' "$path" | shasum -a 256 | cut -d' ' -f1)
    [ $first = 1 ] || echo ','; first=0
    jq -nc --arg p "$path" --arg s "$status" --argjson a "$add" --argjson d "$del" --argjson l "$lines" --arg h "$anchor" --arg prev "$prev" \
      '{path:$p,status:$s,added:$a,removed:$d,lines:$l,anchor:$h} + (if $prev != "" then {previous:$prev} else {} end)'
  done <<<"$list"
  echo ']}'
} | jq -s '.[0] * .[1]' > "$out"
echo "$out: $(jq '.files|length' "$out") files, head $(jq -r .pr.head "$out" | cut -c1-7)"
