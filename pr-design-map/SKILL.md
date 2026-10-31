---
name: pr-design-map
description: Use whenever a pull request is opened or updated, or someone asks for the design map of a PR or a design proposal page: a visual-only, color-coded, dyslexia-friendly page (diagrams, JSON, type hierarchies, per-file cards).
---

# PR design map (visual only)

For every PR, build one page that shows the design as the code stands on the PR's branch. Visuals and code only: no explanatory paragraphs, no figure captions. The page is made to be easy to read for everyone, including people with dyslexia and people who take in structure best through color and pattern: big, well-spaced fonts, no white glare, diagrams and tiles instead of prose. Colors, highlights and repeated patterns make structure easy to see, so every kind of thing gets a consistent color.

## Readability (check every time, before publishing)

- Fonts: Lexend for all text (headings, body, tables, diagrams, buttons) and JetBrains Mono for code, both with letter-spacing 0.02em so letters are not close together. Embed both fonts in the page as base64 woff2 @font-face (latin 400 and 700, from the npm @fontsource packages), so they show the same everywhere. No italics anywhere.
- Sizes: body 18px, line-height 1.7; code 16px, line-height 1.8; tables 16px, table headers 17px. SVG diagrams as displayed: box titles about 22px, subtitles 16-17px, arrow labels 16-18px bold. Never below 14px.
- Bold text is never small: legend labels 15px, pills / badges / chips / status tags 15-16px with roomy padding, buttons 16px bold, tile headings 19-22px.
- No white anywhere. Under the title, a "Background:" row of three buttons with color swatches, saved in localStorage (try/catch), Lavender by default:
  - Lavender: page #cbc4e0; tiles, panels, figures, tables, legend, buttons #dfdaee; table headers #d3cce8; borders #b9b0d6.
  - Sand: page #e3d9c6; tiles, panels, figures, tables, legend, buttons #ede5d6; table headers #e6dcc8; borders #cdbf9f.
  - Dark: dark page, bright text (#f5f7fa).
- Highlight important words in normal text with PASTEL blocks, a different color per kind of word (same color = same kind, everywhere), bold, 4px radius, small padding. Do it automatically with a small script over text outside code, headings, links, pills and the legend; tile headings are not highlighted. Show the highlight colors in the legend ("Highlights" row).
  - Type and class names (CamelCase): pastel blue #bfe3ff (dark: #1f4a6b, text #d6eeff).
  - CONSTANT names: pastel pink #ffc9e0 (dark: #6b2448, text #ffe0ee).
  - Version and decision ids (V104, D1, O5): pastel green #c8f2c8 (dark: #245c2e, text #dcffdc).
  - Numbers: pastel peach #ffdcb8 (dark: #6b3d12, text #ffe9d2).
  - Bold key words in paragraphs and lists: pastel yellow #fff1a6 (dark: #5a4a00, text #fff1a8).
- Diagram labels are one or two words; long lists go in a "Who talks to whom" table under the diagram. Labels never overlap lines or each other (halo in the background color, never a colored glow). Route lines around boxes.
- Code is laid out one statement per line, blank lines between steps, short comment above each part. Variable names say what they hold (current / restored, not before / after).
- Screenshot every page in all three backgrounds (Playwright) and look at it before publishing. Fix anything small, clipped, overlapping, glaring or white.

## Colors (same meaning everywhere)

- Code blocks: soft navy background (#1b2232) in every background. Plain words (variables, punctuation) soft blue-gray (#c9d3e8), never white. Keywords hot pink bold (#ff4fa3), type names light blue regular weight (#6cc9ee, not bold), method calls yellow (#ffd84a), strings green (#7dff7a), numbers and arrows orange (#ffa04a), comments lavender (#c9b8ff). New = solid yellow block with black text; changed = solid orange block with black text. Color code tokens automatically with a small tokenizer script. Show a code color key in the legend.
- Text tiles (cards, build steps, decisions, opportunities, roadmap phases): colored BORDER only. A 2px border in the tile's color and an 8px left edge in the same color. The inside uses the background's tile color with normal ink text and headings: no tinted background, no colored heading. Cycle a bright palette (pink #ff4fa3, blue #2bb3e8, gold #f2b705, green #2fbf4a, orange #ff8a3d, purple #9b6bff) so neighbouring tiles differ, or color by meaning when the tiles have a category (module, kind, status).
- One color per module or external system (for example red, purple, green, orange, blue, brown, gray) for diagram boxes, arrows (color of the caller) and code-block edges.
- One color per command or use case, reused in result matrices and lifecycles.
- Build status colors: built green, next orange, increment 2 purple, increment 3 red.
- Links: one look everywhere, a pill (Lexend 15px bold, letter-spacing 0.03em, padding 4px 13px) with a 2px link-blue border #2bb3e8 on the tile color, text dark blue #065a86 in Lavender and Sand, #8fdcff in Dark, ending in ↗. Inside a link, lines added are green (#13802b; dark #7dff7a) and lines removed are red (#c0262d; dark #ff9a9a), both bold.
- Line-count pill: the Numbers peach, #ffdcb8 with #111 text (dark: #6b3d12 with #ffe9d2), same size as the link pills.
- A legend at the top lists all of these, including a "Links" row: a sample line-count pill ("lines in the file"), "View file ↗", and "View changes +14 −19 ↗" ("added · removed in this PR").

## Links to the code (every page)

Every place that names a file lets the reader open it. Build the links from the PR itself; never guess a path.

- The PR: `https://github.com/<owner>/<repo>/pull/<n>`.
- A file's changes in this PR: `https://github.com/<owner>/<repo>/pull/<n>/files#diff-<sha256 of the file path>` (the hex SHA-256 of the repo-relative path, e.g. `printf '%s' "$path" | sha256sum`).
- The whole file as it stands in the PR: `https://github.com/<owner>/<repo>/blob/<head sha>/<path>`.
- All links open in a new tab (`target="_blank" rel="noopener"`). Links, pills and chips are skipped by the auto-highlight script.
- Line counts: for every file, its total lines at the PR's head commit, and for new or modified files the lines added and removed in this PR (from the PR's files list). Take them from the code and the PR; never estimate.

## Sections, in order

1. Header: title, then a meta line: PR number as a link pill to the PR, branch, short sha, date, file count with +added −removed, then "Updated <date · time · zone>" (the reader's local time zone, e.g. "31 Oct 2026 · 1:30 PM CT", the time you publish) followed by a link pill to the agent session that made or last updated the page, when the session has a URL, labelled with the session's name if known, otherwise "session <first 8 characters of its id>". Never invent a session name. Then background buttons, legend, nav.
2. One request end to end: SVG sequence diagram of a real input, value at each hop.
3. The JSON: every JSON format with real example values, new JSON shapes as trees (what is not understood yet in red), then the same command in each of its shapes.
4. Modules and layers SVG. Directly BELOW it: "New and modified in this PR" as a grid with the diagram's layout (columns = modules, rows = layers; + new, ✎ modified with what changed; "no change" cells). One line per file, and each + / ✎ line ends with a small link pill "+18 −4 ↗" that opens that file's changes in the PR.
5. Type hierarchies and the result matrix.
6. Classes: one tile per file, grouped by module and layer; NEW tag on new classes; highlighted lines for additions. Each tile's heading row: class name, layer chip or NEW / ✎ modified chip, then on the right a line-count pill ("135 lines") and link pills "View file ↗" (whole file in the PR) and, for new or modified files, "View changes +14 −19 ↗" (that file's diff in the PR). Lifecycle SVG for entities with statuses. One tile per DB table / migration, with the same pills.
7. Proposed changes (when a design problem is worth fixing): CURRENT design first, then each MODIFIED option stacked BELOW it (never side by side), each with the code that uses it, then a comparison table and decision tiles with the recommended option marked. No code changes until the user approves.

## Steps

1. Read the PR (number, URL, branch, head commit, date, diff, and the PR's files list with lines added and removed per file), count each file's lines at the head commit, then read the whole affected modules and the design docs on that branch. Note the session URL (and name, if known) for the header.
2. Build the page as one self-contained HTML file, run the readability check, check that links open the right file or diff, fix issues.
3. Publish it titled `<App> Design Map: PR #<n>` (as a hosted page or artifact where your tool offers one, otherwise as an HTML file); republish if the PR already has one. Set the header's Updated time to when you publish.
4. Reply with one line and the link.

## Rules

- Everything shown must come from the code or design docs on the branch. Don't invent classes, fields, paths, line counts or links.
- Short labels in diagrams and short comments in code only; no paragraphs.
- When the user comments on a page, fix that spot, republish, and answer in the comment thread.
