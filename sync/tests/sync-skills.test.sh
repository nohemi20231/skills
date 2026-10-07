#!/usr/bin/env bash
# Tests for scripts/sync-skills.sh. Run: bash sync/tests/sync-skills.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYNC="$ROOT/scripts/sync-skills.sh"
MANIFEST=".claude/skills/.skills-sync-managed"

passed=0
failed=0

# --- helpers -----------------------------------------------------------------

setup() {
  WORK="$(mktemp -d)"
  SRC="$WORK/source"
  DST="$WORK/target"
  mkdir -p "$SRC" "$DST"
  make_skill "$SRC" alpha
  make_skill "$SRC" beta
  mkdir -p "$SRC/alpha/references"
  echo "alpha ref" > "$SRC/alpha/references/notes.md"
  # Folders without a SKILL.md are not skills and must never be copied.
  mkdir -p "$SRC/sync/scripts" "$SRC/scripts" "$SRC/tests" "$SRC/.github"
  echo "x" > "$SRC/scripts/tool.sh"
}

teardown() { rm -rf "$WORK"; }

make_skill() { mkdir -p "$1/$2"; printf -- '---\nname: %s\n---\n%s v1\n' "$2" "$2" > "$1/$2/SKILL.md"; }

run_sync() { (cd "$WORK" && bash "$SYNC" "$SRC" "$DST" "$@") >"$WORK/out" 2>&1; }

fail() { echo "    $1"; return 1; }
assert_file()    { [[ -f "$1" ]] || fail "expected file: $1"; }
assert_no_path() { [[ ! -e "$1" ]] || fail "expected no path: $1"; }
assert_eq()      { [[ "$1" == "$2" ]] || fail "expected [$2], got [$1]"; }

managed() { grep -v '^#' "$DST/$MANIFEST" | sed '/^$/d' | tr '\n' ' ' | sed 's/ $//'; }

t() {
  local name="$1"; shift
  setup
  if "$@"; then echo "ok   - $name"; passed=$((passed + 1))
  else echo "FAIL - $name"; sed 's/^/    | /' "$WORK/out" 2>/dev/null; failed=$((failed + 1)); fi
  teardown
}

# --- tests -------------------------------------------------------------------

copies_all_skills_with_supporting_files() {
  run_sync all || fail "sync exited non-zero" || return 1
  assert_file "$DST/.claude/skills/alpha/SKILL.md" &&
  assert_file "$DST/.claude/skills/alpha/references/notes.md" &&
  assert_file "$DST/.claude/skills/beta/SKILL.md"
}

skips_folders_without_skill_md() {
  run_sync all || fail "sync exited non-zero" || return 1
  assert_no_path "$DST/.claude/skills/sync" &&
  assert_no_path "$DST/.claude/skills/scripts" &&
  assert_no_path "$DST/.claude/skills/tests" &&
  assert_no_path "$DST/.claude/skills/.github"
}

defaults_to_all_when_no_selection_given() {
  run_sync || fail "sync exited non-zero" || return 1
  assert_eq "$(managed)" "alpha beta"
}

copies_only_selected_skills() {
  run_sync beta || fail "sync exited non-zero" || return 1
  assert_no_path "$DST/.claude/skills/alpha" &&
  assert_file "$DST/.claude/skills/beta/SKILL.md"
}

writes_manifest_of_managed_skills() {
  run_sync all || fail "sync exited non-zero" || return 1
  assert_eq "$(managed)" "alpha beta"
}

removes_managed_skill_dropped_from_selection() {
  run_sync all || return 1
  run_sync alpha || fail "second sync exited non-zero" || return 1
  assert_no_path "$DST/.claude/skills/beta" &&
  assert_eq "$(managed)" "alpha"
}

removes_stale_files_inside_a_managed_skill() {
  run_sync all || return 1
  rm "$SRC/alpha/references/notes.md"
  run_sync all || fail "second sync exited non-zero" || return 1
  assert_no_path "$DST/.claude/skills/alpha/references/notes.md"
}

updates_changed_skill_content() {
  run_sync all || return 1
  echo "alpha v2" > "$SRC/alpha/SKILL.md"
  run_sync all || fail "second sync exited non-zero" || return 1
  assert_eq "$(cat "$DST/.claude/skills/alpha/SKILL.md")" "alpha v2"
}

leaves_repo_local_skills_untouched() {
  make_skill "$DST/.claude/skills" local-only
  run_sync all || fail "sync exited non-zero" || return 1
  run_sync alpha || fail "second sync exited non-zero" || return 1
  assert_file "$DST/.claude/skills/local-only/SKILL.md"
}

refuses_to_overwrite_unmanaged_skill_with_same_name() {
  make_skill "$DST/.claude/skills" alpha
  echo "local alpha" > "$DST/.claude/skills/alpha/SKILL.md"
  if run_sync all; then fail "expected non-zero exit"; return 1; fi
  assert_eq "$(cat "$DST/.claude/skills/alpha/SKILL.md")" "local alpha" &&
  assert_no_path "$DST/.claude/skills/beta" &&
  { grep -q "alpha" "$WORK/out" || fail "error should name the skill"; }
}

rejects_unknown_skill_name() {
  if run_sync alpha,nope; then fail "expected non-zero exit"; return 1; fi
  assert_no_path "$DST/.claude/skills/alpha" &&
  { grep -q "nope" "$WORK/out" || fail "error should name the unknown skill"; }
}

honours_custom_destination() {
  (cd "$WORK" && SKILLS_DEST=".github/skills" bash "$SYNC" "$SRC" "$DST" all) >"$WORK/out" 2>&1 ||
    fail "sync exited non-zero" || return 1
  assert_file "$DST/.github/skills/alpha/SKILL.md" &&
  assert_no_path "$DST/.claude/skills"
}

t "copies all skills with supporting files"           copies_all_skills_with_supporting_files
t "skips folders without SKILL.md"                     skips_folders_without_skill_md
t "defaults to all when no selection given"            defaults_to_all_when_no_selection_given
t "copies only selected skills"                        copies_only_selected_skills
t "writes manifest of managed skills"                  writes_manifest_of_managed_skills
t "removes managed skill dropped from selection"       removes_managed_skill_dropped_from_selection
t "removes stale files inside a managed skill"         removes_stale_files_inside_a_managed_skill
t "updates changed skill content"                      updates_changed_skill_content
t "leaves repo-local skills untouched"                 leaves_repo_local_skills_untouched
t "refuses to overwrite unmanaged skill with same name" refuses_to_overwrite_unmanaged_skill_with_same_name
t "rejects unknown skill name"                         rejects_unknown_skill_name
t "honours custom destination"                         honours_custom_destination

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
