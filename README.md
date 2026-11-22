# Skills

Agent skills for Claude Code and GitHub Copilot, one folder per skill, each with a `SKILL.md`.

| Skill | What it does |
|---|---|
| `research-approve-build-verify/` | Adds a feature to an existing app: parallel read-only research, design approval gate, TDD build, fresh-context QA, evidence report. |
| `pr-design-map/` | Builds a visual, color-coded, dyslexia-friendly design map of a pull request: diagrams, JSON, type hierarchies, a tile per file with line counts and links to the changes. A fixed template renders a `map.json` the agent writes plus a `files.json` derived from git; two looks are kept (the default and the classic first version). |

## Layout

```
research-approve-build-verify/   one folder per skill, each with a SKILL.md
pr-design-map/                   and a plugin.json, its GitHub Copilot CLI plugin manifest
CHANGELOG.md                     what changed in each version
sync/                            tooling that delivers skills to app repos
  targets.yml                    which app repos get which skills
  scripts/                       sync script and target parser
  tests/                         tests for both
ci/                              check that every skill is a Copilot CLI plugin, and its tests
fakeTestAll/                     sample screenshots of both pr-design-map designs, from a fake app with two mocked PRs
.github/plugin/marketplace.json  Copilot CLI marketplace: one plugin per skill
.github/workflows/               sync and test workflows (GitHub requires this path)
```

Any top-level folder with a `SKILL.md` is a skill. Add a skill by adding a folder next to the existing ones, with a `plugin.json` and an entry in `.github/plugin/marketplace.json` (see [GitHub Copilot CLI plugins](#github-copilot-cli-plugins)); the tests fail until both are there.

A skill that launches subagents keeps their definitions in `<skill>/agents/<name>.agent.md`: a `name`, a `description` and a `tools` list in the frontmatter, the agent's prompt below it. Claude Code and the Copilot CLI load a project's agents from its `.claude/agents/`, and a synced or linked skill folder is not on that path. So when the skill runs, it copies the definitions the session does not already offer into the project's `.claude/agents/` (see "Agents" in its `SKILL.md`). Edit the definitions here, never the copies.

Only skills I wrote live here. Third-party skills I use are listed, with author, source and license, in [`THIRD_PARTY_SKILLS.md`](THIRD_PARTY_SKILLS.md).

## How app repos get these skills

Developers don't install anything. On each release, a workflow copies the skills into every app repo listed in [`sync/targets.yml`](sync/targets.yml) and opens a pull request there. Once it's merged, everyone gets the skills with a normal `git pull`.

```
tag v1.2.0 here ──▶ Sync skills workflow ──▶ PR into each app repo's .claude/skills/ ──▶ merge ──▶ git pull
```

- **Destination.** Skills land in `.claude/skills/` by default. Claude Code reads that folder, and GitHub Copilot reads it too (alongside `.github/skills/`), so one copy serves both.
- **Ownership.** The workflow only touches the skills it installed, listed in `.claude/skills/.skills-sync-managed` in each app repo. Skills a repo keeps for itself are never changed. If a repo already has its own skill with the same name, the sync fails for that repo instead of overwriting it.
- **One PR per repo and branch.** Later releases update the open sync PR rather than opening another one. The bot's branch is deleted after merge.
- **Branches.** PRs target each repo's default branch unless `branches` says otherwise. Feature branches pick up new skills when they merge main, the same as any other change.

### Releasing a change

The whole repo has one version, `MAJOR.MINOR.PATCH`:

- **MAJOR**: a skill is renamed or removed, or a change breaks how app repos or people use it (its name, its required inputs, the files it writes, the sync manifest).
- **MINOR**: a new skill, or a new step or behavior in an existing one.
- **PATCH**: wording fixes and clarifications that don't change behavior, and fixes to the sync tooling.

1. Every PR that changes a skill folder or `sync/` adds a line under `## Unreleased` in [`CHANGELOG.md`](CHANGELOG.md). The **Changelog** check, a few lines in `.github/workflows/changelog.yml`, fails the PR when `CHANGELOG.md` is not among its changed files; it does not read the line. For a change that needs no line, add the `skip-changelog` label. Tests run on every PR.
2. To release, a PR moves those lines under a new `## X.Y.Z - <title> (<date>)` heading. Merge it.
3. Tag the merge commit and publish the release:
   ```bash
   git tag vX.Y.Z && git push origin vX.Y.Z
   gh release create vX.Y.Z --verify-tag --generate-notes
   ```
4. Review and merge the sync PRs in the app repos.

To sync without a release, run **Sync skills** from the Actions tab.

### Adding an app repo

1. Install the skills-sync GitHub App on the repo (see setup below).
2. Add it to `sync/targets.yml`:
   ```yaml
   targets:
     - repo: my-org/orders-service
       branches: [main]          # optional, default: the repo's default branch
       skills: all               # optional, or a list of skill folder names
   ```

### One-time setup

The workflow writes to other repos, so it authenticates as a GitHub App rather than a personal token.

1. Create a GitHub App (**Settings → Developer settings → GitHub Apps → New GitHub App**, or under the organization's settings for org repos). Turn off the webhook. Give it **Repository permissions**: Contents *Read and write*, Pull requests *Read and write*.
2. Generate a private key for the app.
3. Install the app on the app repos that should receive skills. For repos in an organization, an org owner installs it there.
4. In this repo, add the app's **Client ID** (shown on the app's settings page) as the **variable** `SKILLS_SYNC_CLIENT_ID` and the private key as the **secret** `SKILLS_SYNC_PRIVATE_KEY` (**Settings → Secrets and variables → Actions**).
5. In each app repo, consider turning on **Automatically delete head branches**, and adding a `CODEOWNERS` entry for `.claude/skills/` so hand edits to synced skills get noticed.

## Personal install

To try a skill in every project on your own machine without waiting for a sync, link it into your user skills folder:

```bash
mkdir -p ~/.claude/skills
ln -s ~/workspace/tooling/skills/research-approve-build-verify ~/.claude/skills/research-approve-build-verify
```

Restart Claude Code, then run `/research-approve-build-verify`.

To uninstall, remove the link. The skill folder in this repo is not touched:

```bash
rm ~/.claude/skills/research-approve-build-verify
```

## GitHub Copilot CLI plugins

Each skill is also a plugin for the GitHub Copilot CLI, which gives the CLI the skill in every project without a sync. In a terminal with the CLI, with `OWNER` replaced by the GitHub account this repo lives under:

```bash
copilot plugin marketplace add OWNER/skills
copilot plugin install pr-design-map@skills
copilot plugin install research-approve-build-verify@skills
```

To update the installed plugins:

```bash
copilot plugin update --all
```

To uninstall one plugin:

```bash
copilot plugin uninstall pr-design-map
```

To remove the marketplace and every plugin installed from it (without `--force` the CLI refuses while its plugins are still installed):

```bash
copilot plugin marketplace remove skills --force
```

`copilot plugin disable pr-design-map` switches a plugin off and keeps it installed; `copilot plugin enable pr-design-map` turns it back on. Uninstalling deletes only the CLI's copy under `~/.copilot/installed-plugins/`: this repo and any synced or linked copy of the skill stay as they are.

- **One plugin per skill.** `<skill>/plugin.json` makes the skill folder a plugin whose only skill is its own `SKILL.md`, and `.github/plugin/marketplace.json` lists that folder as the plugin's `source`. No skill file is moved or copied.
- **Keep the manifest in the legacy format.** The CLI loads a plugin's root `SKILL.md` only for a legacy manifest: no `$schema` line, no `skills` path, and no `skills/` directory in the folder. The Agent Plugins format reads skills from `skills/<name>/SKILL.md` only, and that is the one location documented for the other Copilot surfaces (VS Code, the Copilot app), so these plugins are for the CLI.
- **Agents.** `agents/` is the CLI's default agent path for a plugin and it reads `*.agent.md` there, so by the CLI's plugin reference an installed plugin offers the skill's agents without project copies. This has not been tried with the CLI yet; if the session does not offer them, the skill creates the project copies as usual.
- **Next to the sync.** The sync copies `plugin.json` into app repos with the rest of the skill folder. In a repo that has the synced copy, Copilot uses that copy and ignores the plugin's.
- **Checked on every PR.** `ci/check-copilot-plugins.sh` fails when a skill has no manifest, names or descriptions disagree, or the marketplace lists something that is not a skill.
- **`pr-design-map` in Copilot** builds the page (`out/index.html`); publishing it as an artifact is a Claude step.

## Development

```bash
bash sync/tests/sync-skills.test.sh
bash sync/tests/targets-matrix.test.sh
bash ci/tests/check-copilot-plugins.test.sh
bash ci/check-copilot-plugins.sh
```

## License

Copyright 2026 Nohemi Gonzalez Lopez. Licensed under the [Apache License, Version 2.0](LICENSE). Keep the [`NOTICE`](NOTICE) file when redistributing. Third-party skills listed in [`THIRD_PARTY_SKILLS.md`](THIRD_PARTY_SKILLS.md) are not part of this repo and keep their own licenses.
