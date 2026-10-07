#!/usr/bin/env bash
# Copy skills from this repo into a target repo's skills folder.
#
# Usage: sync-skills.sh <source-dir> <target-repo-dir> [all | skill-a,skill-b]
#   SKILLS_DEST  folder inside the target repo (default: .claude/skills,
#                which both Claude Code and GitHub Copilot read)
#
# A skill is any top-level folder in <source-dir> that contains a SKILL.md.
# The script only touches skills it manages, recorded in a manifest file in
# the destination folder. Repo-local skills are never modified, and a name
# clash with one is an error rather than an overwrite.
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <source-dir> <target-repo-dir> [all | skill-a,skill-b]" >&2
  exit 2
fi

source_dir="$(cd "$1" && pwd)"
target_dir="$(cd "$2" && pwd)"
selection="${3:-all}"
dest="$target_dir/${SKILLS_DEST:-.claude/skills}"
manifest="$dest/.skills-sync-managed"

die() { echo "error: $*" >&2; exit 1; }

# Skills available in the source repo.
available=()
for dir in "$source_dir"/*/; do
  [[ -f "$dir/SKILL.md" ]] && available+=("$(basename "$dir")")
done
[[ ${#available[@]} -gt 0 ]] || die "no skills found in $source_dir"

# Skills requested for this target.
if [[ "$selection" == "all" ]]; then
  selected=("${available[@]}")
else
  IFS=',' read -ra selected <<< "$selection"
  for name in "${selected[@]}"; do
    [[ " ${available[*]} " == *" $name "* ]] || die "unknown skill '$name' (available: ${available[*]})"
  done
fi

# Skills this script installed on a previous run.
previous=()
if [[ -f "$manifest" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] || previous+=("$line")
  done < "$manifest"
fi
is_previous() { [[ " ${previous[*]:-} " == *" $1 "* ]]; }

# Validate before changing anything: never overwrite a repo-local skill.
for name in "${selected[@]}"; do
  if [[ -e "$dest/$name" ]] && ! is_previous "$name"; then
    die "'$name' already exists in ${SKILLS_DEST:-.claude/skills} and is not managed by skills sync; rename one of them"
  fi
done

mkdir -p "$dest"

# Remove everything we manage, then copy the selection fresh. This also
# drops skills removed from the selection and files deleted upstream.
for name in "${previous[@]:-}"; do
  [[ -n "$name" ]] && rm -rf "${dest:?}/$name"
done
for name in "${selected[@]}"; do
  cp -R "$source_dir/$name" "$dest/$name"
done

{
  echo "# Managed by skills sync from github.com/nohemi20231/skills."
  echo "# Edit these skills in that repo, not here; local changes are overwritten."
  printf '%s\n' "${selected[@]}"
} > "$manifest"

echo "synced into ${SKILLS_DEST:-.claude/skills}: ${selected[*]}"
