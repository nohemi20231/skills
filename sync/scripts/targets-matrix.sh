#!/usr/bin/env bash
# Turn sync/targets.yml into a GitHub Actions matrix: one JSON entry per
# repo and branch, with defaults filled in.
#
# Usage: targets-matrix.sh [sync/targets.yml]
set -euo pipefail

file="${1:-sync/targets.yml}"

# GitHub runners ship mikefarah/yq; the Python yq wrapper emits JSON by default.
if yq --version 2>&1 | grep -q mikefarah; then
  json="$(yq -o=json '.' "$file")"
else
  json="$(yq '.' "$file")"
fi

jq -c '
  [ (.targets // [])[] as $t
    | if ($t.repo | type) != "string" or ($t.repo | test("^[^/]+/[^/]+$") | not)
      then error("each target needs repo: owner/name, got: \($t | tojson)")
      else . end
    | ($t.branches // [""])[] as $branch
    | { repo: $t.repo,
        branch: $branch,
        skills: (if ($t.skills | type) == "array" then ($t.skills | join(",")) else ($t.skills // "all") end),
        dest: ($t.dest // ".claude/skills") } ]
' <<<"$json"
