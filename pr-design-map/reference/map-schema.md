# map.json reference

The agent writes `map.json` only. `files.json` comes from `scripts/pr-files.sh` (git). `scripts/build.sh` merges both into `data.js`, which `template/app.js` renders. `example/map.json` is a complete worked example.

## Top level

```json
{
  "app": "List Assistant",
  "updated": "1 Nov 2026 · 9:40 PM CT",
  "session": { "url": "https://...", "name": "optional", "id": "fallback id" },
  "modules": [ { "name": "cli", "color": "pink" } ],
  "layers": ["handler", "model", "repository", "schema"],
  "notes": { "<repo path>": { ... } },
  "sections": [ { "type": "...", "title": "...", "files": ["<repo path>"], ... } ],
  "legend": { "Extra row": [ { "name": "built", "color": "green" } ] }
}
```

- `modules`: one color each from pink, blue, gold, green, orange, purple, red, brown, gray (or any CSS color). Columns of the "New and modified" grid and the module diagram boxes.
- `layers`: rows of the grid and the grouping of file tiles.
- `notes[path]`: what the agent knows about a file in the PR. Keys: `module`, `layer`, `class` (tile heading), `change` (two to five words), `lines` (bullets), `code` (see Code), `kind: "table"` for DB tables and migrations.
- `sections[].files`: the repo paths a section was drawn from. Written to `data-files` on the section so the next run can tell which sections a later diff touches.

## Code

```json
{ "lang": "python", "text": "one statement per line\n\n# short comment above each part\n", "added": [3, 4], "changed": [7] }
```

Line numbers are 1-based. Added lines render solid yellow, changed lines solid orange. `lang` picks the comment marker (`#` for python, ruby, sh, yaml; `--` for sql; `//` otherwise).

## Section types

| type | fields | renders |
|---|---|---|
| `sequence` | `actors: [{name, sub, color}]`, `steps: [{from, to, label, value, reply}]`, optional `table` | SVG sequence diagram, value under each arrow, dashed arrows for replies |
| `json` | `items: [{title, value, unknown: ["a.b"], color}]`, `stack` | one tile per JSON shape, unknown keys in red |
| `modules` | `edges: [{from, to, label}]`, optional `table: {columns, rows}` | module boxes with labelled arrows, the "Who talks to whom" table, then the "New and modified in this PR" grid from `files` and `notes` |
| `tree` | `roots: [{name, sub, color, children: [...]}]` | SVG type hierarchy |
| `table` | `columns`, `rows` | table; `✓` and `✗` cells are colored |
| `tiles` | `items: [{title, chip, lines, code, json, color, recommended}]`, `stack` | bordered tiles |
| `code` | `code`, `edge` (color) | one code block |
| `file-tiles` | none | one tile per file in `files`, grouped by module and layer, with line-count and link pills from `files.json`; `kind: "table"` notes go under "Tables and migrations" |
| `lifecycle` | `states: ["OPEN", ...]` or `[{name, color}]`, `transitions: [{from, to, label}]` | SVG state diagram |
| `proposal` | `current: tile`, `options: [tile]`, `comparison: table`, `decisions: [tile]` | CURRENT first, each MODIFIED option stacked below, comparison table, decision tiles with the recommended one marked |

Section `id` defaults to a slug of the title. Links, pills, highlights, legend, nav, background and JSON-tile buttons are generated; the map never carries HTML or styling.

## Prose highlights

Text in `lines`, `change` and table cells is auto-highlighted: CamelCase type names, CONSTANTS, ids like V104 or D1, numbers, and `**key words**`. Keep it to short phrases.
