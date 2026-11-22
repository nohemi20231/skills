#!/usr/bin/env bash
# Tests for ci/check-changelog.sh. Run: bash ci/tests/check-changelog.test.sh
#
# Each test builds a git repo with a base commit, applies a change as a second
# commit, and runs the check on HEAD^1..HEAD, the same range CI uses.
set -uo pipefail

CHECK="$(cd "$(dirname "$0")/.." && pwd)/check-changelog.sh"
# No temp folder, no tests: with an empty $TMP every fixture command below
# (git init, git config, git commit) would run in the caller's repo.
TMP="$(mktemp -d "${TMPDIR:-/tmp}/check-changelog-test.XXXXXX")" && [[ -d "$TMP" ]] \
  || { echo "error: could not create a temp folder" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT
# Fixture git commands must only ever find a fixture repo: forget a repo handed
# down by a git hook (GIT_DIR, GIT_INDEX_FILE) and never look above $TMP for one.
unset $(git rev-parse --local-env-vars)
export GIT_CEILING_DIRECTORIES="$TMP"
passed=0
failed=0

# No fixture, no tests: a test without its fixture repo proves nothing.
no_fixture() { echo "error: could not build a fixture repo" >&2; exit 2; }

# Base commit: skills alpha and beta, a docs folder, sync tooling, a CHANGELOG.
new_repo() {
  local repo; repo="$(mktemp -d "$TMP/repo.XXXXXX")" || return 1
  (
    cd "$repo" || exit 1
    git init -q || exit 1
    git config user.email test@example.com
    git config user.name test
    mkdir -p alpha beta/references docs sync/scripts sync/tests .github/workflows
    echo "# alpha" > alpha/SKILL.md
    echo "notes" > alpha/notes.md
    echo "# beta" > beta/SKILL.md
    echo "notes" > beta/references/notes.md
    echo "notes" > docs/notes.md
    echo "readme" > README.md
    echo "echo sync" > sync/scripts/sync-skills.sh
    echo "echo test" > sync/tests/sync-skills.test.sh
    echo "targets: []" > sync/targets.yml
    echo "name: Sync" > .github/workflows/sync-skills.yml
    echo "name: Tests" > .github/workflows/test.yml
    printf '# Changelog\n\n## Unreleased\n\n## 1.0.0 - First (2026-11-01)\n- first release\n' > CHANGELOG.md
    git add -A && git commit -qm base
  ) || return 1
  echo "$repo"
}

# Changelog edits used inside test changes.
add_unreleased() { awk -v line="$1" '{ print } /^## Unreleased$/ { print ""; print line }' CHANGELOG.md > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md; }
add_to_1_0_0() { awk -v line="$1" '{ print } /^## 1\.0\.0/ { print line }' CHANGELOG.md > CHANGELOG.tmp && mv CHANGELOG.tmp CHANGELOG.md; }

# Applies a change (shell code run in the repo), commits it, runs the check.
# Sets $status and $output.
run_change() {
  local change="$1" repo
  repo="$(new_repo)" || no_fixture
  output="$(cd "$repo" && eval "$change" && git add -A && git commit -qm change --allow-empty \
    && bash "$CHECK" HEAD^1 HEAD 2>&1)"
  status=$?
}

passes() {
  local name="$1" change="$2"
  run_change "$change"
  if [[ $status -eq 0 ]]; then echo "ok   - $name"; passed=$((passed + 1))
  else echo "FAIL - $name (expected pass, exit $status)"; sed 's/^/    /' <<<"$output"; failed=$((failed + 1)); fi
}

# expected_paths: the exact paths the failure must list, one per line, in git order.
fails() {
  local name="$1" change="$2" expected_paths="$3" listed
  run_change "$change"
  listed="$(sed -n 's/^  //p' <<<"$output")"
  if [[ $status -eq 0 ]]; then
    echo "FAIL - $name (expected failure)"; failed=$((failed + 1))
  elif [[ "$listed" != "$expected_paths" ]]; then
    echo "FAIL - $name (wrong paths listed)"; echo "    expected: $expected_paths"; sed 's/^/    /' <<<"$output"; failed=$((failed + 1))
  else echo "ok   - $name"; passed=$((passed + 1)); fi
}

# Bad input must exit 2: never 0 (a pass) and never 1 (a line is missing).
# path: the PATH the check runs with, for a test that swaps in a failing command.
errors() {
  local name="$1" args="$2" path="${3:-$PATH}" repo exit_status
  repo="$(new_repo)" || no_fixture
  (cd "$repo" && PATH="$path" && eval "bash \"\$CHECK\" $args") >/dev/null 2>&1
  exit_status=$?
  if [[ $exit_status -eq 2 ]]; then echo "ok   - $name"; passed=$((passed + 1))
  else echo "FAIL - $name (expected exit 2, got $exit_status)"; failed=$((failed + 1)); fi
}

# A folder whose mktemp always fails, to put first on a PATH.
NO_MKTEMP="$TMP/no-mktemp"
mkdir "$NO_MKTEMP" && printf '#!/bin/sh\nexit 1\n' > "$NO_MKTEMP/mktemp" && chmod +x "$NO_MKTEMP/mktemp" || no_fixture

# --- changes that need no line ---
passes "no changes" ':'
passes "files outside skills and sync tooling" \
  'echo more >> README.md; echo more >> docs/notes.md; echo more >> .github/workflows/test.yml'
passes "sync tests only" 'echo more >> sync/tests/sync-skills.test.sh'
passes "a top-level SKILL.md file is not a skill folder" 'echo x > SKILL.md'

# --- changes that need a line, with one ---
passes "skill changed with a line under Unreleased" \
  'echo more >> alpha/SKILL.md; add_unreleased "- alpha: new step"'

# --- changes that need a line, without one ---
fails "skill changed without a CHANGELOG change" \
  'echo more >> alpha/SKILL.md' 'alpha/SKILL.md'
fails "file deep inside a skill folder" \
  'echo more >> beta/references/notes.md' 'beta/references/notes.md'
fails "new skill" \
  'mkdir gamma && echo "# gamma" > gamma/SKILL.md' 'gamma/SKILL.md'
fails "skill deleted" \
  'git rm -rq alpha' 'alpha/SKILL.md
alpha/notes.md'
fails "skill moved out of the top level" \
  'git mv alpha docs/alpha' 'alpha/SKILL.md
alpha/notes.md'
fails "file moved out of a skill folder" \
  'git mv alpha/notes.md docs/alpha-notes.md' 'alpha/notes.md'
fails "non-ASCII file name in a skill folder" \
  "echo x > alpha/café.md" 'alpha/café.md'
fails "sync script changed" \
  'echo more >> sync/scripts/sync-skills.sh' 'sync/scripts/sync-skills.sh'
fails "sync targets changed" \
  'echo "# x" >> sync/targets.yml' 'sync/targets.yml'
fails "sync workflow changed" \
  'echo "# x" >> .github/workflows/sync-skills.yml' '.github/workflows/sync-skills.yml'
fails "only the paths that need a line are listed" \
  'echo more >> docs/notes.md; echo more >> alpha/SKILL.md; echo "# x" >> sync/targets.yml' 'alpha/SKILL.md
sync/targets.yml'

# --- CHANGELOG changes that do not count ---
fails "line added to a released version, not Unreleased" \
  'echo more >> alpha/SKILL.md; add_to_1_0_0 "- alpha: new step"' 'alpha/SKILL.md'
fails "only a blank line added under Unreleased" \
  'echo more >> alpha/SKILL.md; add_unreleased ""' 'alpha/SKILL.md'
fails "CHANGELOG.md deleted" \
  'echo more >> alpha/SKILL.md; git rm -q CHANGELOG.md' 'alpha/SKILL.md'
fails "CHANGELOG.md renamed" \
  'echo more >> alpha/SKILL.md; git mv CHANGELOG.md CHANGES.md' 'alpha/SKILL.md'
fails "a CHANGELOG.md inside a skill folder does not count" \
  'echo more >> alpha/SKILL.md; echo "- new" > alpha/CHANGELOG.md' 'alpha/CHANGELOG.md
alpha/SKILL.md'

# --- bad input is an error, never a pass ---
errors "unknown base revision" 'no-such-rev HEAD'
errors "missing arguments" ''
errors "no temp folder can be made" 'HEAD HEAD' "$NO_MKTEMP:$PATH"

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
