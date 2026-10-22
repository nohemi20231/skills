---
name: code-quality-sweep
description: "Use on a schedule or on demand during active development: snapshots the working tree, summarizes what changed since the last run, scores the changes for things that change together but live apart (fields, methods, tests, new classes), groups them when tests stay green, logs decisions and keeps a flow diagram current."
---

# Code Quality Sweep

A periodic sweep over work in progress. Each run looks only at what is new since the last run, decides whether the changes point at a design problem, and applies one rule: things that change together live together. Mechanical groupings are applied when the tests stay green. Design questions the sweep cannot settle are written up as a ready-to-run prompt for the user.

Run it from the session where the work happens, so it sees uncommitted changes. A fresh clone sees only commits.

## State

All state lives in `.claude/sweep/` in the app repo. Create the folder and the files on the first run.

| File | Purpose | Committed |
|---|---|---|
| `hashes` | One line per run: `<date> <time> <snapshot-id>`. The first line of each day is that day's baseline. | no |
| `counts.tsv` | Per class: methods added, methods changed, tests added, tests changed, fields added. Appended per run. | no |
| `session-summary.md` | What changed since the baseline, rewritten each run. | no |
| `decisions.md` | Design decisions, one dated entry each. Reversals link the entry they reverse. | yes |
| `flow.md` | Mermaid diagram of the components the session touched and how calls and data flow between them. | yes |
| `next-prompt.md` | Open design questions, each with a prompt ready to paste. Rewritten each run. | no |

Add the uncommitted files to `.gitignore` on the first run if they are not already ignored.

## Phase 0: Hash gate (main agent, no subagents)

1. Take a snapshot that includes the working tree without changing it:
   ```bash
   snap=$(git stash create); [ -z "$snap" ] && snap=$(git rev-parse HEAD)
   ```
   Untracked files are not in the snapshot. List them with `git status --porcelain` and include them in the diff review by hand.
2. Read the last line of `hashes`. If the snapshot id is unchanged and there are no new untracked files, stop. Report "nothing new since <time>" in one line and end the run.
3. Append the new line to `hashes`. If it is the first line today, it is today's baseline.
4. Produce two diffs:
   - **run diff**: `git diff <previous-snapshot> <snap>`, what is new since the last run
   - **session diff**: `git diff <baseline> <snap>`, everything since the day's baseline

If the previous snapshot no longer exists (for example after a rebase), fall back to the baseline, and to `HEAD` if that is gone too. Say so in the summary.

## Phase 1: Parallel read-only research

Launch three subagents in parallel. They are read-only: they must not create, edit or delete files. Give each both diffs and ask for a concise written report with file paths and line references.

1. **Change summarizer**: What changed, per class or module?
   - For each class touched: methods added, methods changed, fields added, fields newly set or read, tests added, tests changed. Return it as a table that can be appended to `counts.tsv`.
   - New classes: name, what problem it solves, whether it is a variant of an existing type (same shape, different values or behaviour).
   - New variables and fields: what each represents, whether it is a variation of a type that already exists.
   - A three-to-eight-line summary of the session so far, for `session-summary.md`.

2. **Co-change miner**: What has history to say about these files?
   - For every file in the session diff, mine the last 200 commits: `git log -200 --name-only --format='commit %h'`.
   - Count pairs of files that appear in the same commit. Report pairs that include a file from the session diff and co-commit three or more times.
   - For each pair, say whether the two files live in the same module, package or folder.
   - Report files from the session diff that have no co-change history, so a new grouping is not confused with a recurring one.

3. **Decision reviewer**: What did we decide earlier, and does the code still agree?
   - Read `decisions.md` and `flow.md`.
   - For each decision, check whether the session diff keeps it, reverses it, or makes it moot. Quote the lines that show it.
   - List components in the session diff that are missing from `flow.md`, and edges in `flow.md` that the code no longer has.

## Phase 2: Score (main agent)

Score each candidate from 0 to 3 on the checklist below. A candidate is a class, a group of files, a new class or a new field.

**Group that changes together but lives apart**
- Session: a field, the methods that set or read it, and the tests for them were all touched this session, and they are spread across more than one class or module: +1.
- History: the same files co-commit three or more times: +1. Five or more: +2.
- The group would fit in one existing class or one new value object without pulling in unrelated code: +1.

**Tests out of step with a class**
- Methods added or changed in the class with no test added or changed: +1 per two methods, capped at 2.
- Tests changed in three or more test classes for one changed method: +1. That is coupling leaking into tests.

**New class**
- A variant of an existing type (same shape, different values): +1. Ask whether a value, an enum, a strategy or a subclass would do instead.
- The report cannot say what problem it solves in one sentence: +1.

**New field or variable**
- A variation of a type that already exists: +1.
- Set in one class and read in another, both touched this session: +1. It is a record waiting to be made.

**Diagram drift**
- Components in the diff missing from `flow.md`, or edges the code no longer has: +1 per item, capped at 2. This never blocks on its own; it is fixed in Phase 4.

Score 0 or 1: note it in the summary, do nothing. Score 2: write a design question (Phase 3b). Score 3: act (Phase 3a) if the action is mechanical, otherwise write the design question.

An action is mechanical when it is one of: move a field and its accessors into the class that reads it, extract a value object from fields that are set and read together, move a test next to the class it tests, or add the missing test for a changed method. Anything that changes a public signature, a persisted schema, or an API contract is a design question, whatever its score.

## Phase 3a: Group what changes together, keep tests green

For each mechanical action, in score order:

1. Run the test suite for the affected module. If it is red before the change, skip the action and record why in `next-prompt.md`. The sweep never starts from red.
2. Launch one subagent per action, in parallel when they touch different files, sequentially when they overlap. Give it the action, the files, and the test command. It makes the smallest change that completes the grouping, runs the same tests, and reports the diff and the test output.
3. If the tests are green after the change, keep it and add a dated entry to `decisions.md`: what was grouped, why (the score lines that fired), and the files. If they are red, revert the change with `git checkout -- <files>` for tracked files, delete any file the subagent created, and write the action up as a design question instead.
4. Never skip, disable or quarantine a test to get green. Never touch files outside the action.

## Phase 3b: Design questions

Rewrite `next-prompt.md`. For each question, in score order:

- One line naming the candidate and the score lines that fired.
- The question in one sentence. Use the ones from the checklist: what problem does this class solve, is this a variant of an existing type, what does this field represent, should these move together.
- A prompt the user can paste as-is to resolve it, naming the files and the two or three options, and asking for the smallest change. Prefer the `research-approve-build-verify` skill when the answer would touch several modules.

## Phase 4: Update the record

Run the three updates in parallel; they touch different files.

1. **Session summary**: rewrite `session-summary.md` from the change summarizer's report, then add a line per Phase 3a action taken and per question raised.
2. **Decisions**: for each reversal the decision reviewer found, add a dated entry that names the entry it reverses. Do not delete old entries.
3. **Flow diagram**: update the Mermaid diagram in `flow.md` so every component in the session diff appears with its edges, and remove edges the code no longer has. Keep it to the components the session touched plus their direct neighbours.

Append the change summarizer's table to `counts.tsv`.

## Phase 5: Report

End with a short report, under 15 lines:

- Since: previous snapshot time, baseline time
- Changed: classes and modules touched this run, one line each
- Grouped: actions applied, with test counts before and after
- Questions: one line each, pointing at `next-prompt.md`
- Drift: decisions reversed, diagram changes
- Nothing new: say so when Phase 0 stopped the run

## Running it on a schedule

The skill is a prompt; something must invoke it. Two options:

- **In a session**: `/loop 20m /code-quality-sweep`. Runs every 20 minutes while the session is open, sees uncommitted work.
- **Scheduled task**: create a scheduled task that fires into the session where the work happens (not a fresh session, which sees only commits) with the prompt `Run the code-quality-sweep skill.` Scheduled tasks are normally limited to hourly at the shortest; the hash gate makes the interval only a matter of how much each run sees, so hourly is fine.

Set the baseline by running the skill once at the start of the day; the first run of a day is the baseline.

## Rules throughout

- Read-only subagents never write. Only Phase 3a subagents change code, and only within their action.
- Keep every change minimal; no unrelated refactors or formatting changes.
- Match the existing codebase's style over personal preference.
- Never put real secrets, credentials or production data in prompts, summaries or fixtures.
