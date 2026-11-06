---
name: research-approve-build-verify
description: Use when adding a feature to an existing app or service: parallel read-only research, design approval gate, TDD implementation, fresh-context QA, evidence report.
---

# Research, Approve, Build, Verify

A workflow for adding a feature to a codebase that already works and must keep working. No single agent both builds and grades the work, and no code is written until the user approves the design.

Skip this workflow for one-line fixes, config tweaks or small isolated changes; use a single agent with TDD instead. Use it when the feature touches several files, modules or services. Docs-only PRs skip the workflow but not the check: before merge, one fresh-context agent compares every claim in the docs with the code, and the author never merges its own unchecked docs PR.

Prefer small slices. When a proposal touches several modules or would add thousands of lines, propose splitting it into PRs that each deliver one behavior.

## Phase 0: Sync (two minutes, every session)

Before any research: `git fetch`, list open PRs (`gh pr list`, or the GitHub tool when the `gh` CLI is not installed), `git log --oneline main..HEAD`, and read the resume line in `docs/architecture/STATE.md`. If that file does not exist, say so in the first message and treat the branch and PR list as the whole state; do not create the file unless the user asks. When another Claude session may be working on the same repo, check which branches it owns and agree that only one session merges to main. A slice, a refactor PR and a design map all start from this known state; skipping it cost the 2026-10-30 session several rounds of "was it pushed, was it approved".

## Approval mode

Each checkpoint shows the recommended option first. The user approves the list of slices once per increment (one line per slice). After that, a slice proposal waits for the user only when it carries an ask-list item (`design-rulebook` SC-7), a contract change, or anything hard to reverse; otherwise show it (one screen) and continue to Phase 3. Without an approved slice list, every proposal waits as before. When the user has said "auto-approve" (or "continue with my recommended options") for the session, the recommended option counts as approved: record the decision with the date in `docs/architecture/STATE.md` (or in the PR description when the repo has no such file) and move on. Contract changes and anything hard to reverse still wait for the user.

## Phase 1: Parallel read-only research

First recall lessons: if the project keeps a file of lessons from earlier PRs (for example the kept lessons of an `agent-grade-and-learn` store, when that skill is installed), search it for the feature's domain words and the modules it touches, and give the matching lessons to every subagent below. If there is no lessons file, write "Lessons used: none kept for this project" in the proposal and continue.

Before editing anything, launch three subagents in parallel. They are read-only: they must not create, edit or delete files. Give each the feature request and ask for a concise written report with file paths and line references.

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

Merge the three reports into a design proposal. Present it in this order:

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

Before showing it, run the `gatekeeper` (Job 4, scope check) on the proposal file and apply its cuts. Then stop for approval as the Approval mode says. Do not write or modify any code before the proposal is approved, by the user or by the approved slice list when it carries no ask-list item. If the user requests changes, revise the proposal and wait again.

## Phase 3: Implement with TDD

After approval, build in red-green-refactor cycles, one row of the approved test plan per cycle (the `test-driven-development` skill). Never write several tests ahead of the code, and never write code for a row before its test has failed.

1. **Red.** Write one test for the next row. Run it and confirm it fails for the expected reason (for a new class: compile error, then an empty stub, then the assertion failure). Commit it alone as `test(<module>): ...`, so the red step is on record.
2. **Green.** Write the least production code that makes that test pass, following the conventions the mapper found. Run the test, then the module's suite. Commit as `feat(<module>): ...` or `fix(<module>): ...`.
3. **Refactor.** With the suite green, clean what the cycle touched: names; extract a shared step before making its third copy; write a repeated value or constructor call once (constant or factory); give a group of parameters that always travel together its own small type; split a class whose imports show it knows too much. Re-run the suite; commit as `refactor(<module>): ...` when anything changed.
4. **Next row**, back to Red.

Tests never depend on real time: inject the clock, await instead of sleeping, and add no test-only overloads to production code.

When every row is green: run the full test suite, run the step 3 checklist (or the project's clean-code skill, when one is installed) over every file the slice touched (inside the slice, so the PR carries its own clean-up; a separate clean-code audit after the PR means a second PR and a second design map for the same change), and update docs, API specs (e.g. OpenAPI) and the manual test matrix.

A QA fix follows the same cycle: a failing test that reproduces the finding, then the fix, one finding per commit, named after it.

Stay within the approved design. If implementation reveals the design will not work as approved, stop and report the problem with a proposed adjustment. Do not improvise a different design.

## Phase 4: Independent QA with fresh context

Launch a QA subagent that has not seen the implementation reasoning. Give it only the feature request, the approved design, and the diff. Ask it to verify and report pass/fail with evidence for each:

1. Existing behavior still works (regression): run the existing test suites for affected modules and services.
2. The new feature path is covered by tests that actually exercise it.
3. API contracts are unchanged for existing consumers, or changes are backward compatible.
4. Docs, API specs and the manual test matrix agree with each other and with the code.
5. The implementation matches the approved architecture diagram.
6. The proposal's "Lessons used" list was followed.
7. Tests use an injected clock, no sleeps and no test-only overloads; no value, call or step is copied three times.
8. Red came first: every `feat`/`fix` commit is preceded by a `test` commit, and the new test fails when run at that `test` commit. Check at least three cycles by checking them out.

The QA agent reports findings only; it does not fix them.

## Phase 5: Fix confirmed failures

Fix only failures the QA agent confirmed with evidence. Do not chase speculative issues. Re-run the relevant tests after each fix. Commit one fix per commit, named after the finding it fixes. If a fix would require changing the approved design, stop and ask the user.

## Phase 6: Report

End with a short report:

- What changed, file by file, in one line each
- Validation evidence: commands run, test counts, pass/fail results
- QA findings and how each was resolved
- Anything deferred or still open
- Size (SC-9): production, test and doc lines changed, and open items before and after

The PR description carries a **Verified** section with this evidence: test commands and counts, plus any diff, sync or manual check run. A claim with no recorded check counts as unverified.

Then one PR per slice, with one line in the change log. A design map (`pr-design-map`, when that skill is installed; otherwise the architecture diagram from the approved proposal goes in the PR description) only when the slice uses the full process (`design-rulebook` SC-6: a new module or service, a contract between modules, a new outside service). Small behavior-preserving refactors that fall out of the review go in the same PR when the same suite guards them; a separate PR only when a contract changes.

## Rules throughout

- Never put real secrets, credentials or production data in prompts, tests or fixtures.
- Keep the diff minimal; no unrelated refactors or formatting changes.
- Match the existing codebase's style over personal preference.
