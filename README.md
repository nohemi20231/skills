# Skills

Agent skills for Claude Code and GitHub Copilot, one folder per skill, each with a `SKILL.md`.

| Skill | What it does |
|---|---|
| `research-approve-build-verify/` | Adds a feature to an existing app: parallel read-only research, design approval gate, TDD build, fresh-context QA, evidence report. |

## How app repos get these skills

Developers don't install anything. On each release, a workflow copies the skills into every app repo listed in [`sync-targets.yml`](sync-targets.yml) and opens a pull request there. Once it's merged, everyone gets the skills with a normal `git pull`.

```
tag v1.2.0 here ──▶ Sync skills workflow ──▶ PR into each app repo's .claude/skills/ ──▶ merge ──▶ git pull
```

- **Destination.** Skills land in `.claude/skills/` by default. Claude Code reads that folder, and GitHub Copilot reads it too (alongside `.github/skills/`), so one copy serves both.
- **Ownership.** The workflow only touches the skills it installed, listed in `.claude/skills/.skills-sync-managed` in each app repo. Skills a repo keeps for itself are never changed. If a repo already has its own skill with the same name, the sync fails for that repo instead of overwriting it.
- **One PR per repo and branch.** Later releases update the open sync PR rather than opening another one. The bot's branch is deleted after merge.
- **Branches.** PRs target each repo's default branch unless `branches` says otherwise. Feature branches pick up new skills when they merge main, the same as any other change.

### Releasing a change

1. Merge the skill change here (tests run on every PR).
2. Tag a release: `git tag v1.2.0 && git push origin v1.2.0`.
3. Review and merge the sync PRs in the app repos.

To sync without a release, run **Sync skills** from the Actions tab.

### Adding an app repo

1. Install the skills-sync GitHub App on the repo (see setup below).
2. Add it to `sync-targets.yml`:
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
4. In this repo, add the app's ID as the **variable** `SKILLS_SYNC_APP_ID` and the private key as the **secret** `SKILLS_SYNC_PRIVATE_KEY` (**Settings → Secrets and variables → Actions**).
5. In each app repo, consider turning on **Automatically delete head branches**, and adding a `CODEOWNERS` entry for `.claude/skills/` so hand edits to synced skills get noticed.

## Personal install

To try a skill in every project on your own machine without waiting for a sync, link it into your user skills folder:

```bash
mkdir -p ~/.claude/skills
ln -s ~/workspace/agents/skills/research-approve-build-verify ~/.claude/skills/research-approve-build-verify
```

Restart Claude Code, then run `/research-approve-build-verify`.

## Development

```bash
bash tests/sync-skills.test.sh
bash tests/targets-matrix.test.sh
```
