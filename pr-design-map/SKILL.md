---
name: pr-design-map
description: Use whenever a pull request is opened or updated, or someone asks for the design map of a PR or a design proposal page: a visual-only, color-coded, dyslexia-friendly page (diagrams, JSON, type hierarchies, per-file cards).
---

# PR design map (visual only)

For every PR, one page that shows the design as the code stands on the PR's branch. Visuals and code only: no explanatory paragraphs, no figure captions. Big, well-spaced fonts, no white glare, diagrams and tiles instead of prose, one consistent color per kind of thing.

The page is a fixed template plus data. You write **map.json** only. Git writes **files.json**. The template renders both.

```
template/   index.html, style.css, app.js, fonts/   the components (never edited per PR)
scripts/    pr-files.sh  build.sh  shoot.sh  extract-map.sh   git facts, assembly, screenshots, map.json back out of a page
reference/  map-schema.md  style-rules.md           what map.json may contain; what the template enforces
example/    files.json  map.json                    a complete worked example
```

## Steps

1. **Facts from git, not from reading.** In the app repo:

   ```
   scripts/pr-files.sh <repo-dir> <pr-number> files.json
   ```

   It writes PR number, URL, owner, repo, branch, head sha, base, date, and for every changed file its status, lines added and removed, total lines at head, and the SHA-256 diff anchor. Never type any of these by hand.

2. **Scope.** Find the previous map for the app (title `<App> Design Map: PR #`). Save its `index.html` to disk with a file-based read (never into the conversation) and run `scripts/extract-map.sh index.html map map.json`; an older multi-file map has `map.json` as its own file. Read that `map.json` (a few KB), never the page. Compare:
   - Same PR, new head: `git diff --name-only <previous head>..<head>`. Empty: update `updated` only. Otherwise rewrite only the sections whose `files` intersect the changed files, and the `notes` of those files.
   - New PR with a previous map: copy `modules`, `layers` and the structural sections (modules, tree, lifecycle, result matrix) whose `files` do not intersect this PR's diff; write new `sequence`, `json` and `notes`; `file-tiles` and the grid rebuild themselves from `files.json`.
   - No previous map: write map.json from scratch, starting from `example/map.json`.

3. **Read only what the rewritten sections need.** The diff, the files in it, and their direct importers and callees found by grep. Not whole modules. `wc -l` first; a file over 400 lines in parts; never generated, vendored or minified files. Design docs only when they name a file in the diff.

4. **Write map.json** per `reference/map-schema.md`. Short labels, two to five word `change` notes, code one statement per line with a short comment above each part. Every path in `notes` and `files` must appear in `files.json`. Note the session URL (and name, if known) in `session`; never invent a name. Set `updated` to the publish time in the reader's zone, e.g. `31 Oct 2026 · 1:30 PM CT`.

5. **Build and check.**

   ```
   scripts/build.sh out/ files.json map.json
   scripts/shoot.sh out/
   ```

   `build.sh` fails if the merge lacks app, PR facts, sections or files. Look at the 2000px crops it produced (rebuilt sections only, in an incremental run), fix map.json, rebuild. Never open the full-height raster.

6. **Publish from disk**, titled `<App> Design Map: PR #<n>`: `out/index.html` only. It carries the CSS, fonts, app.js, map.json and files.json inside it, because claude.ai opens multi-file artifacts only in recent browsers (older Safari shows "This browser isn't supported"). Republishing an older multi-file map: replace mode, so its other files are dropped. Use a file-based publish so no bytes pass through the model. A follow-up refactor PR that only applies the previous map's proposals adds a section to that map, not a new page.

7. Reply with one line and the link.

## Rules

- Everything shown must come from `files.json`, the code or the design docs on the branch. Don't invent classes, fields, paths, counts or links.
- Nothing bulky goes through the model: no base64, no whole-file pastes, no full-height screenshots, no reading a rendered page. Compute on disk, publish from disk.
- Never restyle per PR. Styling lives in the template; a style change is a template change with `reference/style-rules.md` as the spec.
- Proposals (section type `proposal`) are design only. No code changes until the user approves.
- When the user comments on a page, fix that spot in map.json, rebuild, republish `index.html`, and answer in the comment thread.
