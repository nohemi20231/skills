# Changelog

Versions are git tags `vX.Y.Z` on `main`; pushing a tag also runs the **Sync skills** workflow.
How to pick the number and cut a release: "Releasing a change" in the [README](README.md#releasing-a-change).

## Unreleased
- Sync setup: the GitHub App's client ID now goes in the `SKILLS_SYNC_CLIENT_ID` variable, replacing the app ID in `SKILLS_SYNC_APP_ID`. Nothing was configured under the old name.
- CI: every workflow action runs on Node 24 (`actions/checkout` v7, `actions/create-github-app-token` v3, `peter-evans/create-pull-request` v8).

## 1.0.0 - First versioned release (2026-11-01)
- `research-approve-build-verify`: adds a feature to an existing app in phases: sync, parallel read-only research, a design proposal that waits for approval, TDD build, fresh-context QA and an evidence report. It recalls kept lessons, extracts a shared step before its third copy, and keeps tests off real time.
- `pr-design-map`: one visual-only, color-coded page per pull request: diagrams, JSON, type hierarchies, and a tile per file with line counts and links to the changes.
- Sync tooling: on each `v*` tag, the **Sync skills** workflow copies the skills into the app repos listed in `sync/targets.yml` and opens one pull request per repo and branch. The list is empty in this release.
- `docs/skill-sync-proposal.md`: how the GitHub, claude.ai and Mac copies of a skill stay in step, with decisions D-SS-001 to D-SS-008.
