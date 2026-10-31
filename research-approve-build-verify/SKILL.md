---
name: research-approve-build-verify
description: Use when adding a feature to an existing app or service: parallel read-only research, design approval gate, TDD implementation, fresh-context QA, evidence report.
---

# Research, Approve, Build, Verify

A workflow for adding a feature to a codebase that already works and must keep working. No single agent both builds and grades the work, and no code is written until the user approves the design.

Skip this workflow for one-line fixes, config tweaks or small isolated changes; use a single agent with TDD instead. Use it when the feature touches several files, modules or services.

## Phase 0: Sync (two minutes, every session)

Before any research: `git fetch`, `gh pr list`, `git log --oneline main..HEAD`, and read the resume line in `docs/architecture/STATE.md`. When another Claude session may be working on the same repo, check which branches it owns and agree that only one session merges to main. A slice, a refactor PR and a design map all start from this known state; skipping it cost the 2026-10-30 session several rounds of "was it pushed, was it approved".

## Approval mode

Each checkpoint shows the recommended option first. When the user has said "auto-approve" (or "continue with my recommended options") for the session, the recommended option counts as approved: record the decision in `docs/architecture/STATE.md` with the date and move on. Contract changes and anything hard to reverse still wait for the user.

## Phase 1: Parallel read-only research

Before editing anything, launch three subagents in parallel. They are read-only: they must not create, edit or delete files. Give each the feature request and ask for a concise written report with file paths and line references.

1. **Integration mapper**: Where does this feature plug in?
   - Affected services, modules, controllers, beans and packages
   - Configuration (properties/YAML, profiles, feature flags) and how it is loaded
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

## Phase 2: Synthesize and propose. STOP for approval.

Merge the three reports into a design proposal. Present it in this order:

1. **Architecture diagram first**: components touched, new pieces, and how data and calls flow. Then any sequence or data-model diagrams that help.
2. The smallest change that delivers the feature, file by file.
3. Risks from the impact analyst and how the design handles each.
4. The test plan and validation matrix.
5. Open questions.

Then stop and wait for the user's explicit approval. Do not write or modify any code before approval. If the user requests changes, revise the proposal and wait again.

## Phase 3: Implement with TDD

After approval:

1. Write the new tests from the approved test plan first. Run them and confirm they fail for the expected reason.
2. Implement the smallest change that makes them pass, following the conventions the mapper found.
3. Run the full relevant test suite, not just the new tests.
4. Refactor for clarity while keeping tests green. Run the `clean-code` checklist over every file the slice touched here, inside the slice, so the PR carries its own clean-up; a separate clean-code audit after the PR means a second PR and a second design map for the same change.
5. Update docs, API specs (e.g. OpenAPI) and the manual test matrix.

Stay within the approved design. If implementation reveals the design will not work as approved, stop and report the problem with a proposed adjustment. Do not improvise a different design.

## Phase 4: Independent QA with fresh context

Launch a QA subagent that has not seen the implementation reasoning. Give it only the feature request, the approved design, and the diff. Ask it to verify and report pass/fail with evidence for each:

1. Existing behavior still works (regression): run the existing test suites for affected modules and services.
2. The new feature path is covered by tests that actually exercise it.
3. API contracts are unchanged for existing consumers, or changes are backward compatible.
4. Docs, API specs and the manual test matrix agree with each other and with the code.
5. The implementation matches the approved architecture diagram.

The QA agent reports findings only; it does not fix them.

## Phase 5: Fix confirmed failures

Fix only failures the QA agent confirmed with evidence. Do not chase speculative issues. Re-run the relevant tests after each fix. If a fix would require changing the approved design, stop and ask the user.

## Phase 6: Report

End with a short report:

- What changed, file by file, in one line each
- Validation evidence: commands run, test counts, pass/fail results
- QA findings and how each was resolved
- Anything deferred or still open

Then one PR and one design map (`pr-design-map`) per slice. Small behavior-preserving refactors that fall out of the review go in the same PR when the same suite guards them; a separate PR only when a contract changes.

## Rules throughout

- Never put real secrets, credentials or production data in prompts, tests or fixtures.
- Keep the diff minimal; no unrelated refactors or formatting changes.
- Match the existing codebase's style over personal preference.
