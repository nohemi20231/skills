#!/usr/bin/env bash
# Fails when a change touches a skill or the sync tooling without adding a line
# under "## Unreleased" in CHANGELOG.md. The rule is "Releasing a change" in README.md.
#
#   bash ci/check-changelog.sh BASE HEAD      # from the repo root
#
# A path needs a line when it is inside a skill folder (a top-level folder with a
# SKILL.md at BASE or at HEAD, so new, deleted and moved skills count), inside sync/
# other than sync/tests/, or is the sync workflow. Renames count as a delete plus an
# add, so moving a file out of a skill folder counts too.
#
# Exit status: 0 pass, 1 a line is missing, 2 bad arguments.
set -euo pipefail

[[ $# -eq 2 ]] || { echo "usage: $0 BASE HEAD" >&2; exit 2; }
base="$(git rev-parse --verify --quiet "$1^{commit}")" || { echo "error: unknown revision '$1'" >&2; exit 2; }
head="$(git rev-parse --verify --quiet "$2^{commit}")" || { echo "error: unknown revision '$2'" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

has_skill_file() {  # has_skill_file REVISION FOLDER
  git cat-file -e "$1:$2/SKILL.md" 2>/dev/null
}

needs_changelog_line() {  # needs_changelog_line PATH
  local path="$1" folder="${1%%/*}"
  case "$path" in
    sync/tests/*) return 1 ;;
    sync/* | .github/workflows/sync-skills.yml) return 0 ;;
    */*) has_skill_file "$base" "$folder" || has_skill_file "$head" "$folder" ;;
    *) return 1 ;;
  esac
}

# True when HEAD's CHANGELOG.md has a non-blank line, added since BASE, inside "## Unreleased".
adds_unreleased_line() {
  git cat-file -e "$head:CHANGELOG.md" 2>/dev/null || return 1
  git show "$head:CHANGELOG.md" > "$work/changelog"
  git diff -U0 --no-renames --no-color "$base" "$head" -- CHANGELOG.md > "$work/changelog.diff"
  awk -v diff="$work/changelog.diff" '
    FILENAME == diff {                     # collect line numbers of added non-blank lines
      if ($0 ~ /^@@ /) { split($3, range, ","); line = substr(range[1], 2) + 0; in_hunk = 1; next }
      if (in_hunk && $0 ~ /^\+/) { if (substr($0, 2) ~ /[^[:space:]]/) added[line] = 1; line++ }
      next
    }
    /^## / { in_unreleased = ($0 ~ /^## Unreleased[[:space:]]*$/); next }
    in_unreleased && (FNR in added) { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$work/changelog.diff" "$work/changelog"
}

# -z prints paths verbatim, so names with spaces or non-ASCII characters stay intact.
git diff --no-renames --name-only -z "$base" "$head" > "$work/paths"

paths_needing_line=""
while IFS= read -r -d '' path; do
  if needs_changelog_line "$path"; then paths_needing_line+="  $path"$'\n'; fi
done < "$work/paths"

if [[ -z "$paths_needing_line" ]] || adds_unreleased_line; then exit 0; fi

cat >&2 <<MSG
CHANGELOG.md has no new line under "## Unreleased", but these files change a skill or the sync tooling:
${paths_needing_line}
Add a line under "## Unreleased" in CHANGELOG.md. If the change needs none,
add the skip-changelog label to the pull request.
MSG
exit 1
