#!/usr/bin/env bash
# Writes files.json for a design page: a design that has no pull request yet (a design proposal, a Blueprint checkpoint).
# The facts come from git and none is typed: branch, head commit, how many files are uncommitted, and today's date.
# There is no file list: a design page shows no changed files.
# Usage: design-facts.sh <repo-dir> <name> [out=files.json]     <name> is what the page is called, e.g. "Checkpoint 2, service map"
#   <out> is relative to where you run this (pr-files.sh writes relative to the repo). Keep it outside the repository,
#   or the next run counts it as an uncommitted file.
# Needs: jq, git. Outside a git repository the head and the branch are empty and nothing counts as uncommitted;
# before the first commit the head is empty; on a detached head the branch is empty.
set -euo pipefail
dir=$1; name=$2; out=${3:-files.json}
[ -n "${name//[[:space:]]/}" ] || { echo "a design page needs a name" >&2; exit 1; }
[ -d "$dir" ] || { echo "no such directory: $dir" >&2; exit 1; }
head=; branch=; uncommitted=0
if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  head=$(git -C "$dir" rev-parse --verify -q HEAD || true)
  branch=$(git -C "$dir" branch --show-current)
  uncommitted=$(git -C "$dir" status --porcelain --untracked-files=all | wc -l | tr -d ' ')   # every file, not one line for a new folder
fi
jq -n --arg name "$name" --arg branch "$branch" --arg head "$head" --arg date "$(date +%F)" --argjson uncommitted "$uncommitted" \
  '{design: {name: $name, branch: $branch, head: $head, date: $date, uncommitted: $uncommitted}, files: []}' > "$out"
echo "$out: design \"$name\", ${head:+head ${head:0:7}, }$uncommitted uncommitted"
