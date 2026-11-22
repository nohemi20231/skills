#!/usr/bin/env bash
# Writes files.json for a design page: a design that has no pull request yet (a design proposal, a Blueprint checkpoint).
# The facts come from git and none is typed: branch, head commit, how many files are uncommitted, and today's date.
# There is no file list: a design page shows no changed files.
# Usage: design-facts.sh <repo-dir> <name> [out=files.json]     <name> is what the page is called, e.g. "Checkpoint 2, service map"
# Needs: jq, git. Outside a git repository, or before its first commit, head and branch are empty.
set -euo pipefail
dir=$1; name=$2; out=${3:-files.json}
[ -n "$name" ] || { echo "a design page needs a name" >&2; exit 1; }
head=$(git -C "$dir" rev-parse --verify -q HEAD 2>/dev/null || true)
branch=$(git -C "$dir" branch --show-current 2>/dev/null || true)
uncommitted=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
jq -n --arg name "$name" --arg branch "$branch" --arg head "$head" --arg date "$(date +%F)" --argjson uncommitted "${uncommitted:-0}" \
  '{design: {name: $name, branch: $branch, head: $head, date: $date, uncommitted: $uncommitted}, files: []}' > "$out"
echo "$out: design \"$name\", head ${head:0:7}${head:+, }${uncommitted:-0} uncommitted"
