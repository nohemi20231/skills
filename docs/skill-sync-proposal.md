# Skill sync proposal

Status: proposal, research only. Nothing in `sync/` or `.github/` changes until approved.
Research date: 2026-10-31 (all doc URLs accessed that day). Repo state: `main` at 58de6a2.

## 1. Summary

Five copies of a skill can exist, not three: this repo, the claude.ai account, the read-only
mirror of the claude.ai account that Claude Code keeps on the Mac, the Mac's own
`~/.claude/skills/`, and each app repo's `.claude/skills/`. claude.ai has no upload API and no
in-place update, so every option keeps one manual step: delete-and-re-upload a zip. The one new
fact that changes the design: the claude.ai copy is readable on the Mac at
`~/.claude/skills/synced/<org>_<user>/<name>/`, so drift against it can be measured with a `diff`,
no browser or export needed.

Recommendation: C first (a local drift check that reads that mirror), then A as a short release
checklist backed by a zip-builder script, and a decision on private wording (option D) before any
automation. Smallest increment: `sync/scripts/check-drift.sh` plus its test and a README section.

## 2. What is true today

### 2.1 The copies

| Copy | Where | Skills present | Checked how |
|---|---|---|---|
| Repo `main` | `nohemi20231/skills` | `pr-design-map/SKILL.md` (80 lines), `research-approve-build-verify/SKILL.md` (99 lines) | `find` on a fresh clone of 58de6a2 |
| claude.ai account | Settings in the app; uploaded by hand | `pr-design-map`, `agent-grade-and-learn`, `nohemi-code-design`, `test-driven-development` (all `source: plugin`), plus 13 Anthropic skills (`source: anthropic` / `anthropic-example`) | `manifest.json` in the mirror below, field `skills[].source` |
| claude.ai mirror on the Mac | `~/.claude/skills/synced/91e8a761-…_f1449854-…/` with `manifest.json` (`lastUpdated`, `skills[]{skillId,name,description,source,updatedAt,backingPluginId}`) and `.last-complete-round` | same as the row above; `agent-grade-and-learn/` also carries `scripts/skills_for_branch.py` | `ls`, `jq` |
| Mac personal skills | `~/.claude/skills/` | `research-approve-build-verify` is a symlink to `~/workspace/tooling/skills/research-approve-build-verify`; `pr-design-map` is **not** there; `clean-code`, `tdd`, `software-design`, `architecture-diagram`, `blueprint`, `design-rulebook`, `refactor-proposal`, `software-architecture` exist only here | `ls -la` |
| Mac edit backups | `~/.claude/skill-updates/` | `<name>.SKILL.md.before` + `<name>.diff` for `clean-code`, `pr-design-map` (two backups), `research-approve-build-verify`, `tdd`; `design-map-fonts.css` | `ls -la` |
| App repo `list-assistant` | `.claude/skills/` | `pr-design-map` (managed), `research-approve-build-verify` (**unmanaged**), `test-driven-development` (third-party); `.skills-sync-managed` lists only `pr-design-map` | `ls`, `cat` of the manifest |

The Mac tooling clone `~/workspace/tooling/skills` differs from `main` in
`research-approve-build-verify/SKILL.md` by exactly the content of PR #9
(`rabv-lessons-and-verification`); its checked-out branch was not verified (git was off limits in
this sandbox outside the work tree).

### 2.2 Drift measured today

- `pr-design-map`, claude.ai mirror vs `main`: 8 hunks. Every hunk is the content PR #8 left out
  on purpose (PR #8 body: "Left out on purpose (public repo): personal wording, private style-reference
  page links, app-specific module colors"): personal wording for the reader, three artifact slugs as a
  style reference, named module and command colors, a "saved original" aside. The claude.ai copy has
  `updatedAt: 2026-10-31T02:47Z`; PR #8 merged 2026-11-01T00:01Z and was not uploaded back. So the
  claude.ai copy is at the same time *behind* `main` (nothing generic is missing, because #8 took
  the generic parts from this copy) and *deliberately ahead* of it. This is the design constraint
  every option has to answer: the public repo cannot hold what the claude.ai copy holds.
- `agent-grade-and-learn` (247 lines) and `nohemi-code-design` (154 lines): exist only in claude.ai.
  `agent-grade-and-learn` stores its data under `~/workspace/data/agent-grade-and-learn/` (its
  SKILL.md line 19). `nohemi-code-design` is an earlier sibling with an overlapping description.
- `list-assistant`: `pr-design-map/SKILL.md` and `research-approve-build-verify/SKILL.md` are
  byte-identical to `main` (`diff -q`). But because `research-approve-build-verify` is not in
  `.skills-sync-managed`, `sync/scripts/sync-skills.sh <repo> <target> all` against a copy of that
  folder exits 1 with
  `error: 'research-approve-build-verify' already exists in .claude/skills and is not managed by skills sync; rename one of them`
  (`sync/scripts/sync-skills.sh:53-58`). Only `sync-skills.sh … pr-design-map` succeeds, which is what
  list-assistant PR #13 did.
- claude.ai mirror frontmatter is quoted (`name: "pr-design-map"`) while the repo's is not
  (`pr-design-map/SKILL.md:2`). Unknown whether claude.ai rewrites frontmatter on upload or whether the
  uploaded file was already quoted; this matters for any byte-level drift check (see open question 6).

### 2.3 The sync machinery in this repo

- Triggers: `push: tags: ["v*"]` and `workflow_dispatch` (`.github/workflows/sync-skills.yml:8-11`).
  No tag has ever been pushed (`git tag -l` empty) and no GitHub release exists (`gh release list`
  empty); the Actions history shows only the `Tests` workflow, never `Sync skills`.
- `sync/targets.yml:26` is `targets: []`; `sync-skills.yml:43` skips the `sync` job when the matrix
  count is `0`. So even a tag would sync nothing.
- The sync job needs `vars.SKILLS_SYNC_APP_ID` and `secrets.SKILLS_SYNC_PRIVATE_KEY`
  (`sync-skills.yml:70-71`). Names only; values are not in the repo and were not read.
- `sync-skills.sh` discovers a skill as "top-level folder with a `SKILL.md`"
  (`sync/scripts/sync-skills.sh:28-31`), copies the selection fresh (`:64-69`) and writes the managed
  manifest (`:71-75`).
- Tests: `sync/tests/sync-skills.test.sh` 12 pass locally. `sync/tests/targets-matrix.test.sh`
  fails 5 of 7 on the Mac with `yq: command not found` (`sync/scripts/targets-matrix.sh:11-15`
  requires `yq`; CI runners ship it, `targets-matrix.sh:10`). The Mac has `jq`, `zip`, `unzip`,
  `shasum`, no `yq`.
- `README.md:39-45` documents release = tag; `README.md:68-77` documents the personal symlink
  install, which is how `research-approve-build-verify` reaches the Mac today.
- `.gitignore:4` excludes `test-driven-development/` (third-party, listed in
  `THIRD_PARTY_SKILLS.md:9`).

### 2.4 What claude.ai and Claude Code offer (docs)

- "Custom Skills do not sync across surfaces … Skills uploaded to claude.ai must be separately
  uploaded to the API. Skills uploaded through the API are not available on claude.ai. Claude Code
  Skills are filesystem-based and separate from both claude.ai and the API."
  https://platform.claude.com/docs/en/agents-and-tools/agent-skills/overview § Cross-surface availability.
  The Skills API (`POST /v1/skills`, `POST /v1/skills/{id}/versions`) targets the Developer Platform
  workspace, not a claude.ai account. **No programmatic upload to claude.ai exists.** Option A2
  (automated upload) is off the table.
- claude.ai upload: "Package your skill folder as a ZIP file", Customize > Skills > "+" > "Create
  skill" > "Upload a skill". Failure causes listed: "Missing required skill.md file", "Skill folder
  name doesn't match the skill name", "ZIP file exceeds size limits" (no number given). No in-place
  update is documented; the only path is remove, then "add the skill again by re-uploading the file".
  https://support.claude.com/en/articles/12512180-using-skills-in-claude
- Same article: "Skills you've enabled in your Claude settings also load in Claude Code" (v2.1.273+),
  one-way, not when signed in with an API key or a cloud provider.
- Claude Code: "Claude Code downloads your account's skills into `~/.claude/skills/synced/` in the
  background, then checks claude.ai for changes while the session runs." "Claude Code downloads
  synced skills and never uploads them." "If you or Claude edit a file under
  `~/.claude/skills/synced/`, the change isn't saved to your claude.ai account, and a later sync can
  overwrite or remove it." Synced skills are `/anthropic-skills:<name>`; with a local skill of the
  same short name, `/<name>` runs the local one. Personal skills (`~/.claude/skills/`) load in "All
  your projects on this machine, but not Cowork or cloud sessions"; project skills
  (`.claude/skills/`) load in "Sessions in this repository, but not cloud threads in a project".
  https://code.claude.com/docs/en/skills
  Consequence: a cloud session sees only the claude.ai copy and the repo's `.claude/skills/`; the
  Mac copy is invisible to it. The claude.ai copy is load-bearing.
- Frontmatter limits (platform overview § Skill structure): `name` ≤ 64 chars, lowercase letters,
  digits, hyphens, no `anthropic` / `claude`; `description` non-empty, ≤ 1,024 chars.

### 2.5 Not checked

- The claude.ai UI itself (no browser in this session); the zip size limit; whether claude.ai
  normalizes frontmatter quoting on upload.
- The tooling clone's current branch and uncommitted state (git outside the sandbox work tree).
- Whether `manifest.json` / `.last-complete-round` are a stable interface; both are undocumented.
  A drift check must treat the mirror as best-effort input and say when it is missing or stale.
- Whether the skills-sync GitHub App is installed on list-assistant.

## 3. Options

Shared vocabulary: "upload" = delete the skill in claude.ai, then upload a zip whose single
top-level folder is `<name>/` containing `SKILL.md` (and any `scripts/`, `references/`). A zip built
with `zip -r <name>.zip <name> -x '*.DS_Store'` from the repo root has exactly that layout (trial
run on `pr-design-map`: 2 entries).

### A. GitHub as the single source, upload step after each merge

- **Repo changes.** `README.md` § Releasing a change gets step 2b: "build the zip, upload to
  claude.ai". A `sync/scripts/build-zips.sh [name…]` writes `dist/<name>.zip` plus
  `dist/<name>.sha256`, with a test in `sync/tests/build-zips.test.sh` (fixture skills, assert zip
  listing and that non-skill folders are skipped). A PR template checkbox "uploaded to claude.ai"
  (optional).
- **Manual steps left.** Per merged skill change: pull, run the builder, delete the old skill in
  claude.ai, upload, open one Claude Code session so the mirror refreshes.
- **Failure modes.** The step is forgotten (PR #8 says "After merge: run the Sync skills workflow"
  and no upload happened); edits made in a session land in `~/.claude/skill-updates/*.diff` and in
  claude.ai but never in a repo PR; the public repo still cannot carry the personal wording, so the
  upload would strip it unless D exists. Nothing notices any of this.
- **Effort.** Small: one script, one test file, README edits. Automated variant impossible
  (§ 2.4).

### B. Release-time zips on `v*` tags

- **Repo changes.** New job `release` in `sync-skills.yml` (or a separate `release.yml`) after
  `test`: run `build-zips.sh`, attach `dist/*.zip` and the checksums to the GitHub Release for the
  tag with `gh release create "$GITHUB_REF_NAME" dist/*` (needs `permissions: contents: write` for
  that job only; today the workflow is `contents: read`, `sync-skills.yml:13-14`). `build-zips.sh` is
  the same script as in A (L-002: one shared step, two callers).
- **Manual steps left.** Cut the tag; download the zip from the release page; delete and upload in
  claude.ai. The download is the only thing B removes from A, and it replaces a `zip` command with
  a browser round-trip.
- **Failure modes.** Tags are never cut (none exist in 25 days of commits), so skills would ship to
  claude.ai only on release day while `main` moves on; everything in A's list still applies.
- **Effort.** Medium: workflow job, permission change, release notes, plus A's script and test.
  Value is low while `targets.yml` is empty and tags are not part of the habit.

### C. Drift check

- **Repo changes.** `sync/scripts/check-drift.sh [--claude-ai DIR] [--personal DIR] [--app DIR…]`
  that, for every skill in the repo and every skill in the claude.ai mirror, prints one line:
  `<name> <copy> same | differs (+a/-b lines) | only-in-<copy> | not-present`. Defaults:
  claude.ai mirror = the single bucket under `~/.claude/skills/synced/`, personal =
  `~/.claude/skills/`, apps = none unless given. Exit 1 when anything differs. Comparison by
  content (`diff`/`cmp`), never by mtime (L-003: no wall clock in tests). Frontmatter compared
  after stripping surrounding quotes from `name:`/`description:` values so claude.ai's quoting is not
  reported as drift (pending open question 6). Test file `sync/tests/check-drift.test.sh` in the
  style of `sync/tests/sync-skills.test.sh` (mktemp fixtures, `t "name" fn`).
- **Where it runs.** Only where the mirror is: the Mac. Candidates, cheapest first: by hand;
  from the `wip` alias; as step 0 of `research-approve-build-verify` § Phase 0 Sync
  (`research-approve-build-verify/SKILL.md:12`); as a Claude Code `SessionStart` hook. A CI job
  cannot see the claude.ai copy, so C stays local.
- **Manual steps left.** Running it, then deciding per line: PR the claude.ai change into the
  repo, or upload the repo version.
- **Failure modes.** Detects, does not fix. The mirror refreshes at session start and "while the
  session runs" (docs), so a check immediately after an upload can read the old copy; the output
  must print the mirror's `updatedAt` so a stale read is visible. Intentional private divergence
  (D) shows as permanent drift unless the check compares against the overlaid build.
- **Effort.** Small-medium: one script, one test file, README section.

### D. Private overlay (added)

The claude.ai copy of `pr-design-map` carries content Nohemi chose to keep out of the public repo.
Options A-C either strip it on upload or flag it forever. Two ways to keep "one source" true:

- **D1.** Keep a private patch per skill (`<name>.private.patch`, kept outside this public repo, for
  example next to `~/.claude/skill-updates/`), applied by `build-zips.sh --overlay DIR` before
  zipping. The drift check compares the mirror against the overlaid output. Cost: patches rot when
  the public file changes (`patch` reports rejects, which is the signal to fix them).
- **D2.** Accept generic wording everywhere (what PR #8 wrote) and upload that. Zero machinery;
  loses the personal phrasing and the style-reference links in claude.ai sessions. The links can
  move to a private page or to the lessons store instead of the skill.

### E. Bring the claude.ai-only skills into the repo (added)

`agent-grade-and-learn` and `nohemi-code-design` have no repo copy, so no option covers them until
they do. `agent-grade-and-learn` references Nohemi by name throughout and stores data under
`~/workspace/data/...`; it would need either D or a generic rewrite before it can live in a public
repo. Alternative: a private repo `nohemi20231/skills-private` with the same `sync/` layout; this
repo's scripts already treat "any top-level folder with a `SKILL.md`" as a skill, so they would
work unchanged there.

### F. Drop the claude.ai copy (added, rejected)

Not viable: cloud sessions and claude.ai chats load only the claude.ai copy (§ 2.4), and the
`anthropic-skills:*` listing in every Claude Code session comes from it.

## 4. Recommendation and first increment

Order: **C → A → D/E decision → B only if tags become a habit.**

Why C first: today nobody can see the drift without a browser and a side-by-side read; PR #8 took
a session to reconcile one file. With the mirror on disk, a check is a `diff` with a report format,
and it also answers "did the upload take?" after A's manual step. A without C repeats PR #8.

**Increment 1 (one PR, one commit per finding):**

1. `sync/scripts/check-drift.sh` + `sync/tests/check-drift.test.sh`. Tests, each watched failing
   first: reports `same`; reports `differs` with line counts; reports `only-in-claude-ai`; reports
   `only-in-repo`; ignores quoting differences in frontmatter values only; exits 1 on any
   difference, 0 otherwise; says `mirror not found` and exits 2 when the directory is absent;
   skips folders without `SKILL.md` on both sides; never reads mtimes (grep the tree for `-newer`,
   `stat`, `date`, `sleep` as the targeted smell).
2. README § "Checking drift against claude.ai and the Mac" with the one command.
3. No workflow change, no `targets.yml` change, no zip builder yet.

**Increment 2:** `build-zips.sh` + test + README checklist (option A). At that point the skill
discovery loop exists in `sync-skills.sh:28-31`, `check-drift.sh` and `build-zips.sh`: three copies,
so extract `sync/scripts/lib/skills.sh` (`list_skills DIR`) in that PR (L-002), with
`sync-skills.test.sh` as the regression net.

**Increment 3 (needs decisions below):** D1 or D2; E for the two claude.ai-only skills; fix the
list-assistant manifest so `all` works (add `research-approve-build-verify` to
`.claude/skills/.skills-sync-managed` there, or remove the unmanaged folder and re-sync), then add
list-assistant to `sync/targets.yml` so the existing workflow finally has a target.

## 5. Open questions for Nohemi

1. **Private wording.** D1 (private patch applied at build), D2 (generic everywhere), or keep
   maintaining the claude.ai copy by hand and let C flag it as "differs, expected"? This decides
   whether "single source" is achievable at all.
2. **agent-grade-and-learn / nohemi-code-design.** Move `agent-grade-and-learn` into this repo
   (generic rewrite) or into a private skills repo? Delete `nohemi-code-design` in claude.ai as
   superseded?
3. **list-assistant.** Add it to `targets.yml` now and fix its `.skills-sync-managed` so the
   workflow's `all` selection works? Is the GitHub App already installed on it (not checked)?
4. **Where C runs.** By hand, in `wip`, in RABV Phase 0, or as a `SessionStart` hook? A hook
   adds a few hundred ms per session start and prints on every drift.
5. **Mac pr-design-map.** Add `~/.claude/skills/pr-design-map -> ~/workspace/tooling/skills/pr-design-map`
   like the existing `research-approve-build-verify` symlink? Then `/pr-design-map` runs the repo
   copy locally and `/anthropic-skills:pr-design-map` the claude.ai copy, which is also what makes
   drift visible in the `/` menu.
6. **Frontmatter quoting.** One experiment settles it: upload a zip built from `main` and diff the
   mirror next session. If claude.ai rewrites the frontmatter, C normalizes; if not, C compares
   bytes.
7. **yq on the Mac.** `brew install yq` so `targets-matrix.test.sh` passes locally, or accept that
   it is CI-only and say so in the README?
8. **Tags.** Are `v*` releases still the intended delivery to app repos, or should the workflow
   also run on `push: branches: [main]` once a target exists?

## 6. Lessons used

- **L-001 (check every claim in the code).** Every path:line above was read in a fresh clone of
  58de6a2; the sync script was run against a copy of list-assistant's skills folder to confirm the
  `all` failure; the tests were run to find the `yq` dependency; the mirror's manifest was read with
  `jq` for the skill list and `source` values; doc quotes were fetched on 2026-10-31. § 2.5 lists
  what was not checked.
- **L-002 (extract the shared step before the third copy).** The skill-discovery loop will have
  three callers after increment 2; the plan names that PR as the extraction point and keeps
  increment 1 at two copies. `build-zips.sh` is one script for options A and B.
- **L-003 (tests: watch each assertion fail, no sleeps or wall clock, grep for the smell).**
  Increment 1 lists the assertions, mandates content comparison instead of mtimes, and names the
  grep (`-newer`, `stat`, `date`, `sleep`) over `sync/`. Test style follows
  `sync/tests/sync-skills.test.sh:14-47`.
- **L-004 (one fix per commit, named with its finding; scope changes get a decision id).** This
  PR is one commit, docs only. Each increment above is its own PR; its scope decisions (questions
  1-8) get ids `D-SS-001…` in the PR body when answered.

## 7. Decisions (answered 2026-10-31)

| Id | Question | Decision |
|---|---|---|
| D-SS-001 | 1 private wording | **D1.** One private patch per skill, kept outside this repo and applied when the upload zip is built. The drift check compares the claude.ai copy against the patched output. |
| D-SS-002 | 2 claude.ai-only skills | `agent-grade-and-learn` moves to a private repo with the same `sync/` layout. `nohemi-code-design` is superseded and gets deleted in claude.ai. |
| D-SS-003 | 3 list-assistant | Add `nohemi20231/list-assistant` to `sync/targets.yml`; the same PR checks that the GitHub App is installed. |
| D-SS-004 | 4 where C runs | In `wip` only: one line per drifted skill, silent when all match. No hook, no RABV step. |
| D-SS-005 | 5 Mac symlink | Yes. `~/.claude/skills/pr-design-map -> <repo>/pr-design-map`, same pattern as `research-approve-build-verify`. Done 2026-10-31. |
| D-SS-006 | 6 frontmatter quoting | Run the experiment once: upload a zip whose frontmatter is unquoted, diff the mirror next session. Until the result is in, the check normalizes quoting in frontmatter values. |
| D-SS-007 | 7 yq | Installed on the Mac (`brew install yq`, v4.54.1); both test suites pass locally (12 + 7). |
| D-SS-008 | 8 trigger | `v*` tags only. No `push: branches: [main]` trigger. |

Increment 1 stays as in § 4: `sync/scripts/check-drift.sh` + `sync/tests/check-drift.test.sh` + README section; `wip` calls the script (D-SS-004). Increment 2: `build-zips.sh --overlay DIR` (D-SS-001, D-SS-006). Increment 3: `targets.yml` entry (D-SS-003). The private repo (D-SS-002) is its own task.
