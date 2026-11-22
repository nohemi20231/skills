---
name: research-approve-build-verify
description: Use when adding a feature to an existing app or service: parallel read-only research, design approval gate, TDD implementation, fresh-context QA, evidence report.
---

# Research, Approve, Build, Verify

A workflow for adding a feature to a codebase that already works and must keep working. No single agent both builds and grades the work, and no code is written until the user approves the design.

Skip this workflow for one-line fixes, config tweaks or small isolated changes; use a single agent with TDD instead. Use it when the feature touches several files, modules or services. Docs-only PRs skip the workflow but not the check: before merge, one fresh `read-only-analyst` (see Agents) compares every claim in the docs with the code, and the author never merges its own unchecked docs PR.

Prefer small slices. When a proposal touches several modules or would add thousands of lines, propose splitting it into PRs that each deliver one behavior.

## Phase 0: Sync (two minutes, every session)

Before any research: `git fetch`, list open PRs (`gh pr list`, or the GitHub tool when the `gh` CLI is not installed), `git log --oneline main..HEAD`, and read the resume line in `docs/architecture/STATE.md`. If that file does not exist, say so in the first message and treat the branch and PR list as the whole state; do not create the file unless the user asks. Create the workflow's agents when the session does not offer them (see Agents). When another Claude session may be working on the same repo, check which branches it owns and agree that only one session merges to main. A slice, a refactor PR and a design map all start from this known state; skipping it cost the 2026-10-30 session several rounds of "was it pushed, was it approved".

## Approval mode

Each checkpoint shows the recommended option first. The user approves the list of slices once per increment (one line per slice). After that, a slice proposal waits for the user only when it carries an ask-list item (`design-rulebook` SC-7), a contract change, or anything hard to reverse; otherwise show it (one screen) and continue to Phase 3. Without an approved slice list, every proposal waits as before. When the user has said "auto-approve" (or "continue with my recommended options") for the session, the recommended option counts as approved: record the decision with the date in `docs/architecture/STATE.md` (or in the PR description when the repo has no such file) and move on. Contract changes and anything hard to reverse still wait for the user.

## Scope rules

The SC ids come from the `design-rulebook` skill. When it is installed, its text is the rule; otherwise these lines are.

- **SC-1 Source or park.** An item enters scope only with a source: the user's words, a cited production failure that would hit this deployment, or a cited law, carrier or platform rule that applies to it. Anything else is one line in `docs/parked.md`.
- **SC-4 Slice cap.** One PR, about 500 changed production lines (tests excluded), at most 5 technical defaults. Over the cap, cut to the part the user can use and park the rest; the cut is not a question.
- **SC-6 Process fits risk.** Default is the light loop: research, a one-screen proposal, the scope check, TDD, one QA pass, a PR. Full process (ADR, contract logs, design map) only for a new module or service, a change to a contract between modules, or a new outside service.
- **SC-7 Ask-list.** Ask the user only about money (a new paid service, or more than $5/month added), anything hard to undo (deleting data, registrations, external accounts), a request that would exceed twice the slice cap, or behaviour that notifies the user more often or changes what happens to their data.
- **SC-9 Size.** Each PR reports production, test and doc lines and open items. Flag docs growing faster than code, or open items rising three PRs in a row.

## Agents

Apart from the optional `gatekeeper`, the subagents this workflow launches are two agent definitions, kept next to this file in `agents/`. A definition lets the harness enforce what a prompt can only ask for: the tool list.

| Agent | Tools | Launched for |
|---|---|---|
| `read-only-analyst` | Read, Grep, Glob | the three research roles (Phase 1), the scope check when there is no `gatekeeper` (Phase 2), the docs-only check |
| `qa-verifier` | Read, Grep, Glob, Bash | independent QA (Phase 4): runs suites and reads git; no editing tools, and its rules forbid changing code, tests, docs or config through the shell |

**Create them before the first launch** (in Phase 0, when the workflow runs). For each agent the session does not already offer:

1. Copy `agents/<name>.agent.md` to `.claude/agents/<name>.md` in the project, unchanged. Claude Code and the Copilot CLI both read that folder. Use the file tool, not a shell `cp`: a sandboxed shell is denied that folder.
2. Name the files you created in the first message.
3. Commit them alone, before any other commit on the branch: `chore(agents): add research-approve-build-verify agents`. They are tooling and do not count toward the slice cap (SC-4).

Never overwrite a copy that is already there. When it differs from the definition here, say so in the first message, keep using the copy, and replace it only when the user says so.

Claude Code usually offers a new agent within seconds, without a restart. When the session still does not offer it (a session that had switched into a git worktree did not, 2026-11-21), use the fallback below for this session; the named agent is there from the next one.

**Launch them by name**, the independent ones in a single message so they run in parallel. An agent starts with an empty context, so the brief is all it knows. Send what its phase lists (for a research role: the feature request in the user's words, the role and its points, and the matching lessons), as file paths rather than pasted contents. Leave your own conclusion out; an agent that is handed the expected answer tends to return it.

**Check that nothing changed.** A tool list does not cover the fallback, and `qa-verifier` has a shell. So record these four lines before every launch (`gatekeeper` included; once for agents launched together) and again after the last report:

```
git rev-parse --abbrev-ref HEAD
git rev-parse HEAD
git diff HEAD --binary | git hash-object --stdin
git status --porcelain
```

Take the first record for `qa-verifier` after your own full test run, not before it, so that what the suite rewrites (a formatter, a lockfile, generated files) is already in the record. While an agent runs, do not change files and do not run installs, builds or tests yourself. Then compare:

- All four are the same: continue.
- Only the status list differs, and every changed line is a new `??` entry: untracked files appeared, usually test output that `.gitignore` does not cover. Continue, and name those lines in the Phase 6 report.
- Anything else differs (the branch, the commit, the diff hash, or any other line of the status list): a tracked file, the index or the history changed while the agent ran. Stop, and show the user `git status --short`, `git diff HEAD --stat` and, when the commit moved, `git log --oneline` from the recorded commit to `HEAD`. Do not undo it yourself.

The check does not see a push, a change outside the repository, or a change to a file git does not track (ignored, or already untracked before the launch).

**When the harness cannot run them** (it has no named agents, `.claude/agents/` cannot be written, or the session does not offer an agent you just created): read the definition, put its body (everything below the frontmatter) at the top of an ordinary subagent's prompt, and state the tool list in the brief. Where that subagent has no search tool of its own, allow it read-only shell commands for searching, and nothing that writes. Say in the Phase 6 report that the agents ran through the fallback: the tool limits were asked for, not enforced.

**Writing a definition.** A definition holds what stays the same from slice to slice: the job, the tool list, the rules and the shape of the report. Checklists stay in this file and travel in the brief, so a project's copy does not go stale when a checklist changes. The frontmatter has three fields: `name` (the file name without `.agent.md`), `description` (when to launch it and what it never does) and `tools` (the shortest list that does the job; leaving the line out grants every tool). It sets no `model`, so the agent runs on the session's model on either harness. To change one of the two, or to add one to the workflow, edit `agents/` next to this file in the repo this skill comes from, never a project's copy.

## Phase 1: Parallel read-only research

First recall lessons: if the project keeps a file of lessons from earlier PRs (for example the kept lessons of an `agent-grade-and-learn` store, when that skill is installed), search it for the feature's domain words and the modules it touches, and give the matching lessons to every subagent below. If there is no lessons file, write "Lessons used: none kept for this project" in the proposal and continue.

Before editing anything, launch three `read-only-analyst` agents in parallel (see Agents), one per role below. They are read-only: they must not create, edit or delete files. Give each the feature request, its role and the points under it, and ask for a concise written report with file paths and line references.

1. **Integration mapper**: Where does this feature plug in?
   - Affected services, modules, packages and entry points (controllers, handlers, commands, jobs)
   - Configuration (config files, environment variables, profiles, feature flags) and how it is loaded
   - Authentication and authorization paths the feature passes through
   - Data model and persistence touched, including migrations
   - Existing conventions the change must follow: naming, layering, error handling, logging, DTO/mapping patterns

2. **Impact analyst**: What could break?
   - Shared code and libraries used elsewhere
   - API contracts (REST, events, messages) and every known consumer of them, including other services
   - Backward compatibility, schema changes, data migration risks
   - Concurrency, transactions, caching, and performance concerns
   - Anything in the code that contradicts assumptions in the request

3. **Test strategist**: What must be proven?
   - Existing tests covering the affected area and their gaps
   - New unit, integration and contract tests needed, listed as concrete cases
   - A validation matrix: existing behaviors to regression-check × new behaviors to verify
   - Manual test steps where automation is not practical

## Phase 2: Synthesize, scope-check, propose

Merge the three reports into a design proposal. The analysts cannot run commands: run the ones their reports name under "Unverified" before those points go into the proposal. Present it in this order:

1. **Architecture diagram first**: components touched, new pieces, and how data and calls flow. Then any sequence or data-model diagrams that help.
2. The smallest change that delivers the feature, file by file.
3. Risks from the impact analyst and how the design handles each.
4. The test plan and validation matrix.
5. **Lessons used**: each matching lesson id and how the design follows it, or "not relevant" with a reason.
6. **Scope table**: every scope item with its source (`design-rulebook` SC-1: the user's words, a cited failure that would hit this deployment, or a cited rule that applies to it), the estimated production lines against the slice cap (SC-4), and the parked items, one line each, added to `docs/parked.md`.
7. Questions for the user: only ask-list items (SC-7). Decide everything else and list it as technical defaults (at most 5).

The proposal opens with the lines `- **Branch:** <branch>` and `- **Status:** ...`; before any code, the status reads `APPROVED` with its source (the user's words, or the approved slice list). A PR check or hook may match these lines. Check every claim the proposal makes about existing code against the code itself (file and line) before writing it down. Write user-facing text (replies, error messages) word for word in the proposal.

A proposal for a small slice looks like this (headings and order fixed, content illustrative):

```
## Design: order cancellation by customer
- **Branch:** feature/order-cancel
- **Status:** PROPOSED

### Architecture
[diagram: OrderController -> OrderService.cancel -> OrderRepository; emits OrderCancelled event]

### Change, file by file
- src/orders/OrderController.java:88  add POST /orders/{id}/cancel, delegates to service
- src/orders/OrderService.java:140    add cancel(id): rejects unless status is NEW or CONFIRMED
- src/orders/OrderStatus.java:12      add CANCELLED
- V12__order_cancelled.sql            new status value, no column change

User-facing text: "Order {id} can no longer be cancelled because it has shipped."

### Risks
- BillingService reads OrderStatus (BillingService.java:57): CANCELLED is ignored there today -> add an explicit branch and a test.

### Test plan
New: cancel NEW order succeeds; cancel SHIPPED order returns 409 with the text above; event emitted once.
Regression: existing OrderServiceTest and BillingServiceTest suites.

### Lessons used
- L-014 (idempotent state changes): cancel on an already CANCELLED order returns 200, no second event.

### Scope
| Item | Source | Est. lines |
| cancel endpoint + status | user's words | ~60 / cap |
Parked: automatic refund (docs/parked.md)

### Questions for the user
- none (technical default: no automatic refund in this slice)
```

Before showing it, run the `gatekeeper` (Job 4, scope check) on the proposal file and apply its cuts. When that agent is not installed, give the proposal file and the Scope rules above to a fresh `read-only-analyst`, ask it which items to cut or park and why, and apply its cuts. Then stop for approval as the Approval mode says. Do not write or modify any code before the proposal is approved, by the user or by the approved slice list when it carries no ask-list item. If the user requests changes, revise the proposal and wait again.

## Phase 3: Implement with TDD

After approval, build in red-green-refactor cycles, one row of the approved test plan per cycle (the `test-driven-development` skill, when installed; the steps below are the rule either way). Never write several tests ahead of the code, and never write code for a row before its test has failed.

1. **Red.** Write one test for the next row. Run it and confirm it fails for the expected reason (for a new class: compile error, then an empty stub, then the assertion failure). Commit it alone as `test(<module>): ...`, so the red step is on record.
2. **Green.** Write the least production code that makes that test pass, following the conventions the mapper found. Run the test, then the module's suite. Commit as `feat(<module>): ...` or `fix(<module>): ...`.
3. **Refactor.** With the suite green, clean what the cycle touched: names; extract a shared step before making its third copy; write a repeated value or constructor call once (constant or factory); give a group of parameters that always travel together its own small type; split a class whose imports show it knows too much. Re-run the suite; commit as `refactor(<module>): ...` when anything changed.
4. **Next row**, back to Red.

Tests never depend on real time: inject the clock, await instead of sleeping, and add no test-only overloads to production code.

When every row is green: run the full test suite, run the step 3 checklist (or the project's clean-code skill, when one is installed) over every file the slice touched (inside the slice, so the PR carries its own clean-up; a separate clean-code audit after the PR means a second PR and a second design map for the same change), and update docs, API specs (e.g. OpenAPI) and the manual test matrix.

A QA fix follows the same cycle: a failing test that reproduces the finding, then the fix, one finding per commit, named after it.

Stay within the approved design. If implementation reveals the design will not work as approved, stop and report the problem with a proposed adjustment. Do not improvise a different design.

## Phase 4: Independent QA with fresh context

Launch the `qa-verifier` agent (see Agents), which has not seen the implementation reasoning. Give it only the feature request, the approved design, the diff and the checks below. Ask it to verify and report pass, fail or not verified, with evidence, for each:

1. Existing behavior still works (regression): run the existing test suites for affected modules and services.
2. The new feature path is covered by tests that actually exercise it.
3. API contracts are unchanged for existing consumers, or changes are backward compatible.
4. Docs, API specs and the manual test matrix agree with each other and with the code.
5. The implementation matches the approved architecture diagram.
6. The proposal's "Lessons used" list was followed.
7. Tests use an injected clock, no sleeps and no test-only overloads; no value, call or step is copied three times. Every new or changed test follows the project's test-style rules (in `CLAUDE.md` or equivalent), when it has them.
8. Red came first: every `feat`/`fix` commit is preceded by a `test` commit, and the new test fails when run at that `test` commit. Check at least three cycles, each in a temporary copy of its `test` commit.

The QA agent reports findings only; it does not fix them. A check that comes back not verified is not a pass: it goes in the Phase 6 report as still open.

## Phase 5: Fix confirmed failures

Fix only failures the QA agent confirmed with evidence. Do not chase speculative issues. Re-run the relevant tests after each fix. Commit one fix per commit, named after the finding it fixes. If a fix would require changing the approved design, stop and ask the user.

## Phase 6: Report

End with a short report:

- What changed, file by file, in one line each
- Validation evidence: commands run, test counts, pass/fail results, whether the agents ran by name or through the fallback, and what the nothing-changed check found
- QA findings and how each was resolved
- Anything deferred or still open
- Size (SC-9): production, test and doc lines changed, and open items before and after

The PR description carries a **Verified** section with this evidence: test commands and counts, plus any diff, sync or manual check run. A claim with no recorded check counts as unverified.

The PR description also carries one line that names every skill loaded for the slice. A grader reads it from the PR, so it works for a build whose session logs are not on the grader's machine:

```
Skills loaded: research-approve-build-verify, clean-code, test-driven-development
```

- List each skill once, in the order first loaded: the ones this session loaded and the ones an agent's report says it loaded. Start the list at the first load and keep it through the slice; a summarized context can drop it.
- Write the bare name: drop any prefix up to the last colon, so `some-plugin:clean-code` is `clean-code`.
- Only skills that were loaded, never ones that would have applied. With none, write `Skills loaded: none`.
- Keep it one line that starts with `Skills loaded:`, and update it when a later commit on the PR loads another skill.

Then one PR per slice, with one line in the change log. A design map (`pr-design-map`, when that skill is installed; otherwise the architecture diagram from the approved proposal goes in the PR description) only when the slice uses the full process (`design-rulebook` SC-6: a new module or service, a contract between modules, a new outside service). Small behavior-preserving refactors that fall out of the review go in the same PR when the same suite guards them; a separate PR only when a contract changes.

## Rules throughout

- Never put real secrets, credentials or production data in prompts, tests or fixtures.
- Keep the diff minimal; no unrelated refactors or formatting changes.
- Match the existing codebase's style over personal preference.
