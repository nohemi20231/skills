#!/usr/bin/env bash
# Check that every skill in this repo is packaged as a GitHub Copilot CLI plugin.
#
# Usage: check-copilot-plugins.sh [repo-dir]   (default: the repo this script is in)
#
# A skill is any top-level folder that contains a SKILL.md and is not ignored
# by git. Each one is a plugin of its own, listed in
# .github/plugin/marketplace.json:
#   - <skill>/plugin.json names the plugin after its folder and describes it.
#   - The manifest sets no "$schema" and no "skills", and the folder has no
#     skills/ directory. The Copilot CLI loads a plugin's root SKILL.md only
#     for a manifest in the legacy format that keeps the default skills path,
#     and only when that path does not exist.
#   - The marketplace lists the plugin once, with the folder as its source and
#     the same description as the manifest.
# The marketplace lists nothing that is not a skill here.
set -uo pipefail

command -v jq >/dev/null || { echo "error: jq is required" >&2; exit 2; }

repo="$(cd "${1:-$(dirname "$0")/..}" && pwd)" || exit 2
marketplace="$repo/.github/plugin/marketplace.json"
kebab_case='^[a-z0-9]+(-[a-z0-9]+)*$'
name_rule="kebab-case (lowercase letters, numbers, hyphens), at most 64 characters"
errors=0

fail() { echo "error: $*" >&2; errors=$((errors + 1)); }
die() { echo "error: $*" >&2; exit 1; }

is_skill() { [[ -f "$repo/$1/SKILL.md" ]]; }
is_plugin_name() { [[ "$1" =~ $kebab_case && ${#1} -le 64 ]]; }
is_git_ignored() { git -C "$repo" check-ignore -q "$1" 2>/dev/null; }

skill_names() {
  local path name
  for path in "$repo"/*/; do
    name="$(basename "$path")"
    if is_skill "$name" && ! is_git_ignored "$name"; then echo "$name"; fi
  done
}

marketplace_has_required_fields() {
  jq -e '(.name | type == "string") and (.owner.name | type == "string") and (.plugins | type == "array")' \
    "$marketplace" >/dev/null
}

marketplace_entry_count() {
  jq --arg name "$1" '[.plugins[] | select(.name == $name)] | length' "$marketplace"
}

marketplace_entry_field() {
  jq -r --arg name "$1" --arg field "$2" '.plugins[] | select(.name == $name) | .[$field]' "$marketplace"
}

check_manifest() {
  local skill="$1" manifest="$2"
  is_plugin_name "$skill" \
    || fail "$skill: a plugin name is $name_rule"
  [[ "$(jq -r '.name' "$manifest")" == "$skill" ]] \
    || fail "$skill: plugin.json \"name\" must be \"$skill\""
  jq -e '.description | type == "string" and length > 0 and length <= 1024' "$manifest" >/dev/null \
    || fail "$skill: plugin.json needs a \"description\" of at most 1024 characters"
  jq -e '(has("$schema") or has("skills")) | not' "$manifest" >/dev/null \
    || fail "$skill: plugin.json must not set \"\$schema\" or \"skills\", or the Copilot CLI stops loading the root SKILL.md"
  [[ ! -d "$repo/$skill/skills" ]] \
    || fail "$skill: a skills/ directory hides the root SKILL.md from the Copilot CLI"
}

check_marketplace_entry() {
  local skill="$1" manifest="$2" entry_source
  if [[ "$(marketplace_entry_count "$skill")" -ne 1 ]]; then
    fail "$skill: marketplace.json must list it exactly once"
    return
  fi
  entry_source="$(marketplace_entry_field "$skill" source)"
  [[ "${entry_source#./}" == "$skill" ]] \
    || fail "$skill: marketplace \"source\" must be \"./$skill\""
  [[ "$(marketplace_entry_field "$skill" description)" == "$(jq -r '.description' "$manifest")" ]] \
    || fail "$skill: plugin.json and marketplace.json descriptions differ"
}

check_skill() {
  local skill="$1" manifest="$repo/$1/plugin.json"
  if [[ ! -f "$manifest" ]]; then
    fail "$skill: plugin.json is missing"
    return
  fi
  if ! jq -e 'type == "object"' "$manifest" >/dev/null; then
    fail "$skill: plugin.json is not a JSON object"
    return
  fi
  check_manifest "$skill" "$manifest"
  check_marketplace_entry "$skill" "$manifest"
}

check_marketplace_lists_only_skills() {
  local name
  while IFS= read -r name; do
    is_plugin_name "$name" && is_skill "$name" \
      || fail "marketplace.json lists \"$name\", which is not a skill folder"
  done < <(jq -r '.plugins[].name' "$marketplace")
}

[[ -f "$marketplace" ]] || die ".github/plugin/marketplace.json is missing"
marketplace_has_required_fields || die ".github/plugin/marketplace.json needs name, owner.name and plugins"
is_plugin_name "$(jq -r '.name' "$marketplace")" || fail "marketplace.json \"name\" is $name_rule"

skills=()
while IFS= read -r skill; do skills+=("$skill"); done < <(skill_names)
[[ ${#skills[@]} -gt 0 ]] || die "no skills found in $repo"

for skill in "${skills[@]}"; do check_skill "$skill"; done
check_marketplace_lists_only_skills

if [[ "$errors" -gt 0 ]]; then
  echo "$errors problem(s): see \"GitHub Copilot CLI plugins\" in README.md" >&2
  exit 1
fi
echo "ok: ${#skills[@]} skill(s) packaged as Copilot CLI plugins: ${skills[*]}"
