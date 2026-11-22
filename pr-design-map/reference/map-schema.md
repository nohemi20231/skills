# map.json reference

The agent writes `map.json` only. `files.json` comes from `scripts/pr-files.sh` (git). `scripts/build.sh` embeds both in one self-contained `index.html` (JSON blocks `#files-json` and `#map-json`), which `template/app.js` merges and renders; `scripts/extract-map.sh` pulls `map.json` back out of a published page. `example/map.json` is a complete worked example.

## Top level

```json
{
  "app": "List Assistant",
  "updated": "1 Nov 2026 · 9:40 PM CT",
  "session": { "url": "https://...", "name": "optional", "id": "fallback id" },
  "summary": ["New **add** command creates a Task", "Task gains a status field"],
  "modules": [ { "name": "cli", "color": "pink" } ],
  "layers": ["handler", "model", "repository", "schema"],
  "notes": { "<repo path>": { ... } },
  "sections": [ { "type": "...", "title": "...", "files": ["<repo path>"], ... } ],
  "legend": { "Extra row": [ { "name": "built", "color": "green" } ] }
}
```

- A design page (SKILL.md, "Design page") has no pull request: its files.json comes from `scripts/design-facts.sh` and carries `design: {name, branch, head, date, uncommitted}`, no `pr` and an empty `files`; `build.sh` refuses a mix. It is titled `<App> Design: <name>`. There are no `notes`. `modules` draws its boxes and arrows without the changed-files grid, and `file-tiles` is left out.
- `template` (optional): `"classic"` renders the page with `template-classic/` (the first look: IBM Plex, light and dark, numbered sections, layered module columns, text trees, cards); omitted or `"default"` uses `template/`. `build.sh -t` overrides it.
- `summary`: what the PR changes, three to six bullets of one short line each (a single string is one bullet). Rendered under the PR facts as a "What changed" tile that folds (Hide ▴ / Show ▾), open at first; auto-highlighted like `lines`. Omitted: no tile.
- `modules`: one color each from pink, blue, gold, green, orange, purple, red, brown, gray (or any CSS color; classic also knows teal). Columns of the "New and modified" grid and the module diagram boxes.
- `layers`: rows of the grid and the grouping of file tiles.
- `notes[path]`: what the agent knows about a file in the PR. Keys: `module`, `layer`, `class` (tile heading), `change` (two to five words), `lines` (bullets), `code` (see Code), `kind`: `"table"` for DB tables and migrations (both templates group them apart); classic also shows `record`, `interface`, `enum` or `helper` as a colored kind chip.
- `sections[].caption` (diagram sections: sequence, modules, hub, tree, lifecycle): one string of one or two sentences shown under the diagram, 30 words at most, auto-highlighted like `lines`. What it says is in SKILL.md, step 4; `build.sh` reports a diagram without one.
- `sections[].files`: the repo paths a section was drawn from. Written to `data-files` on the section so the next run can tell which sections a later diff touches.

## Code

```json
{ "lang": "python", "text": "one statement per line\n\n# short comment above each part\n", "added": [3, 4], "changed": [7] }
```

Line numbers are 1-based. Added lines get a `+` gutter mark, a yellow left bar and a faint yellow tint; changed lines a `~`, an orange bar and tint. Token colors stay. `lang` picks the comment marker (`#` for python, ruby, sh, yaml; `--` for sql; `//` otherwise).

## Section types

| type | fields | renders |
|---|---|---|
| `sequence` | `actors: [{name, sub, color}]`, `steps: [{from, to, label, value, reply}]`, optional `table` | SVG sequence diagram, value under each arrow, dashed arrows for replies |
| `json` | `items: [{title, value, unknown: ["a.b"], color, tag}]`, `stack` | one tile per JSON shape, unknown keys in red; classic shows `tag` (a package or source, e.g. `parser.api · ReplyDecoder`) in small mono above the tile |
| `modules` | `edges: [{from, to, label}]`, optional `table: {columns, rows}` | module boxes with labelled arrows, the "Who talks to whom" table, then the "New and modified in this PR" grid from `files` and `notes` |
| `hub` | `hub: {name, sub, color}`, `groups: [{name, sub, color, members: ["..."], note, down, up, link, readOnly}]`, optional `top: {name, sub, color, down, up}`, `store: {name, sub, color, link}`, `down`, `up`, `table` | SVG hub map for one coordinator and the groups it drives: the `top` actor, one wide hub band, a box per group listing its members, one wide store band. `down`, `up` and `link` are label strings. `down` and `up` label the arrows between the hub and every group, and a group's own values win; with no `up` (or `up: false` on one group) there is a single arrow down. `link` labels a group's arrow to the store (the store's `link` unless the group has its own): a head at each end, dashed from the store to the group with `readOnly`, no arrow with `link: false` |
| `tree` | `roots: [{name, sub, color, tag, children: [...]}]` | SVG type hierarchy (classic: a text tree per root, `sealed` before a root with children, `sub` as a comment, `tag` above) |
| `table` | `columns`, `rows`, optional `colors` | table; `✓` and `✗` cells are colored. `colors` gives one color per column (a command's color, say); classic colors that column's header and its `●` marks with it |
| `tiles` | `items: [{title, chip, lines, code, json, color, recommended}]`, `stack` | bordered tiles. A `chip` naming a kind (record, interface, enum, helper / class, table) colors the tile by kind in classic |
| `code` | `code`, `edge` (color) | one code block |
| `file-tiles` | none | one tile per file in `files`, grouped by module and layer, with line-count and link pills from `files.json`; `kind: "table"` notes go under "Tables and migrations". Then two lists, one row per file, folded at first with the count in the bar: "Tests" (a note with module or layer `tests`, a test folder such as `src/test/` or `tests/`, or a test file name such as `FooTest`, `FooIT`, `test_foo.py`, `foo.test.ts`) and "Other files" (every file without a note) |
| `lifecycle` | `states: ["OPEN", ...]` or `[{name, color}]`, `transitions: [{from, to, label}]` | SVG state diagram |
| `proposal` | optional `current: tile`, `options: [tile]`, `comparison: table`, `decisions: [tile]` | CURRENT first (left out when there is no current design), each MODIFIED option stacked below, comparison table, decision tiles with the recommended one marked |

Section `id` defaults to a slug of the title. Links, pills, highlights, the Key panel, the section picker and sidebar, the Settings panel and the Hide / Show diagram folds are generated; the map never carries HTML or styling.

## Prose highlights

Text in `summary`, `caption`, `lines`, `change` and table cells is auto-highlighted: CamelCase type names, CONSTANTS, ids like V104 or D1, numbers, and `**key words**`. Keep it to short phrases.
