#!/usr/bin/env bash
# Tests for ci/check-copilot-plugins.sh. Run: bash ci/tests/check-copilot-plugins.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/check-copilot-plugins.sh"
passed=0
failed=0

write_manifest() {
  local repo="$1" skill="$2" json="$3"
  echo "$json" > "$repo/$skill/plugin.json"
}

edit_marketplace() {
  local file="$1/.github/plugin/marketplace.json" jq_filter="$2"
  jq "$jq_filter" "$file" > "$file.new" && mv "$file.new" "$file"
}

# A repo with two skills, each a valid plugin listed in the marketplace, and
# one folder that is not a skill. The two sources show both accepted spellings.
new_repo() {
  local repo
  repo="$(mktemp -d "${TMPDIR:-/tmp}/copilot-plugins-test.XXXXXX")" || return 1
  mkdir -p "$repo/.github/plugin" "$repo/alpha" "$repo/beta" "$repo/docs"
  touch "$repo/alpha/SKILL.md" "$repo/beta/SKILL.md"
  write_manifest "$repo" alpha '{"name": "alpha", "description": "Does alpha."}'
  write_manifest "$repo" beta '{"name": "beta", "description": "Does beta."}'
  cat > "$repo/.github/plugin/marketplace.json" <<'JSON'
{
  "name": "skills",
  "owner": { "name": "someone" },
  "plugins": [
    { "name": "alpha", "source": "./alpha", "description": "Does alpha." },
    { "name": "beta", "source": "beta", "description": "Does beta." }
  ]
}
JSON
  echo "$repo"
}

# Each case names a function that changes a fresh repo, given as $1.
run_check() {
  local change="$1" repo status
  repo="$(new_repo)" || { echo "cannot create a temporary repo"; return 1; }
  if "$change" "$repo"; then
    bash "$CHECK" "$repo" 2>&1
    status=$?
  else
    echo "cannot prepare the case with $change"
    status=1
  fi
  rm -rf "$repo"
  return "$status"
}

check_passes() {
  local name="$1" change="$2" output
  if output="$(run_check "$change")"; then
    echo "ok   - $name"; passed=$((passed + 1))
  else
    echo "FAIL - $name"; echo "    output: $output"; failed=$((failed + 1))
  fi
}

check_fails() {
  local name="$1" change="$2" expected="$3" output
  if output="$(run_check "$change")"; then
    echo "FAIL - $name (expected an error)"; failed=$((failed + 1))
  elif [[ "$output" != *"$expected"* ]]; then
    echo "FAIL - $name"; echo "    expected: $expected"; echo "    output:   $output"; failed=$((failed + 1))
  else
    echo "ok   - $name"; passed=$((passed + 1))
  fi
}

unchanged() { :; }

ignored_local_skill() {
  git init -q "$1" && echo "local-only/" > "$1/.gitignore" \
    && mkdir "$1/local-only" && touch "$1/local-only/SKILL.md"
}

no_manifest() { rm "$1/beta/plugin.json"; }

manifest_not_json() { write_manifest "$1" beta '{"name": "beta",'; }

other_plugin_name() {
  write_manifest "$1" beta '{"name": "other", "description": "Does beta."}'
}

underscore_name() {
  mkdir "$1/My_Skill" && touch "$1/My_Skill/SKILL.md" \
    && write_manifest "$1" My_Skill '{"name": "My_Skill", "description": "Does it."}' \
    && edit_marketplace "$1" '.plugins += [{"name": "My_Skill", "source": "./My_Skill", "description": "Does it."}]'
}

no_description() { write_manifest "$1" beta '{"name": "beta"}'; }

agent_plugins_schema() {
  write_manifest "$1" beta \
    '{"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json", "name": "beta", "description": "Does beta."}'
}

skills_path_in_manifest() {
  write_manifest "$1" beta '{"name": "beta", "description": "Does beta.", "skills": "custom/"}'
}

skills_directory() { mkdir "$1/beta/skills"; }

unlisted_skill() {
  mkdir "$1/gamma" && touch "$1/gamma/SKILL.md" \
    && write_manifest "$1" gamma '{"name": "gamma", "description": "Does gamma."}'
}

listed_twice() { edit_marketplace "$1" '.plugins += [.plugins[1]]'; }

source_elsewhere() { edit_marketplace "$1" '.plugins[1].source = "./alpha"'; }

other_description() { edit_marketplace "$1" '.plugins[1].description = "Does something else."'; }

entry_without_skill() { rm "$1/beta/SKILL.md"; }

no_marketplace() { rm "$1/.github/plugin/marketplace.json"; }

marketplace_without_owner() { edit_marketplace "$1" 'del(.owner)'; }

marketplace_name_with_spaces() { edit_marketplace "$1" '.name = "My Skills"'; }

no_skills() { rm "$1/alpha/SKILL.md" "$1/beta/SKILL.md"; }

check_passes "every skill is a listed plugin; other folders are ignored" unchanged
check_passes "a skill folder ignored by git is skipped" ignored_local_skill

check_fails "skill without a plugin.json" no_manifest \
  'beta: plugin.json is missing'
check_fails "plugin.json is not valid JSON" manifest_not_json \
  'beta: plugin.json is not a JSON object'
check_fails "plugin named differently from its folder" other_plugin_name \
  'beta: plugin.json "name" must be "beta"'
check_fails "plugin name is not kebab-case" underscore_name \
  'My_Skill: a plugin name is kebab-case'
check_fails "manifest without a description" no_description \
  'beta: plugin.json needs a "description"'
check_fails "manifest in the Agent Plugins format" agent_plugins_schema \
  'beta: plugin.json must not set "$schema" or "skills"'
check_fails "manifest moves the skills path" skills_path_in_manifest \
  'beta: plugin.json must not set "$schema" or "skills"'
check_fails "skill with a skills/ directory" skills_directory \
  'beta: a skills/ directory'

check_fails "skill missing from the marketplace" unlisted_skill \
  'gamma: marketplace.json must list it exactly once'
check_fails "skill listed twice in the marketplace" listed_twice \
  'beta: marketplace.json must list it exactly once'
check_fails "marketplace source points at another folder" source_elsewhere \
  'beta: marketplace "source" must be "./beta"'
check_fails "marketplace and manifest descriptions differ" other_description \
  'beta: plugin.json and marketplace.json descriptions differ'
check_fails "marketplace lists a folder that is not a skill" entry_without_skill \
  'marketplace.json lists "beta", which is not a skill folder'

check_fails "no marketplace.json" no_marketplace \
  'marketplace.json is missing'
check_fails "marketplace without an owner" marketplace_without_owner \
  'marketplace.json needs name, owner.name and plugins'
check_fails "marketplace name is not kebab-case" marketplace_name_with_spaces \
  'marketplace.json "name" is kebab-case'
check_fails "repo without skills" no_skills \
  'no skills found'

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
