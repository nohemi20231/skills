#!/usr/bin/env bash
# Tests for scripts/targets-matrix.sh. Run: bash tests/targets-matrix.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MATRIX="$ROOT/scripts/targets-matrix.sh"
passed=0
failed=0

check() {
  local name="$1" yaml="$2" expected="$3" actual
  local f; f="$(mktemp)"; printf '%s\n' "$yaml" > "$f"
  actual="$(bash "$MATRIX" "$f" 2>&1)"; rm -f "$f"
  if [[ "$(jq -cS . <<<"$actual" 2>/dev/null)" == "$(jq -cS . <<<"$expected")" ]]; then
    echo "ok   - $name"; passed=$((passed + 1))
  else
    echo "FAIL - $name"; echo "    expected: $expected"; echo "    actual:   $actual"; failed=$((failed + 1))
  fi
}

check_fails() {
  local name="$1" yaml="$2" f
  f="$(mktemp)"; printf '%s\n' "$yaml" > "$f"
  if bash "$MATRIX" "$f" >/dev/null 2>&1; then echo "FAIL - $name (expected error)"; failed=$((failed + 1))
  else echo "ok   - $name"; passed=$((passed + 1)); fi
  rm -f "$f"
}

check "empty targets gives empty matrix" \
  'targets: []' \
  '[]'

check "defaults: repo default branch, all skills, .claude/skills" \
  'targets:
  - repo: acme/app' \
  '[{"repo":"acme/app","branch":"","skills":"all","dest":".claude/skills"}]'

check "one entry per branch" \
  'targets:
  - repo: acme/app
    branches: [main, develop]' \
  '[{"repo":"acme/app","branch":"main","skills":"all","dest":".claude/skills"},
    {"repo":"acme/app","branch":"develop","skills":"all","dest":".claude/skills"}]'

check "skill list becomes comma-separated" \
  'targets:
  - repo: acme/app
    skills: [alpha, beta]
    dest: .github/skills' \
  '[{"repo":"acme/app","branch":"","skills":"alpha,beta","dest":".github/skills"}]'

check "multiple repos" \
  'targets:
  - repo: acme/one
  - repo: acme/two
    skills: all' \
  '[{"repo":"acme/one","branch":"","skills":"all","dest":".claude/skills"},
    {"repo":"acme/two","branch":"","skills":"all","dest":".claude/skills"}]'

check_fails "target without repo is an error" \
  'targets:
  - skills: all'

check_fails "repo not in owner/name form is an error" \
  'targets:
  - repo: just-a-name'

echo
echo "$passed passed, $failed failed"
[[ $failed -eq 0 ]]
