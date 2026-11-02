# Style rules the template implements

`template/style.css` and `template/app.js` implement everything below. Read this only when changing the template; map.json never carries styling.
## Readability (check every time, before publishing)

- Fonts: Lexend for all text and JetBrains Mono for code, letter-spacing 0.02em, no italics. Shipped as four woff2 files under `fonts/` (latin 400 and 700 from the npm @fontsource packages), never base64.
- JSON tile themes: under the Background row, a "JSON tiles:" row with two buttons, saved in localStorage like the background, Cell type by default:
  - Cell type: the "New and modified in this PR" tile font as a named style, `:root{--cell-font:var(--font-mono);--cell-size:15px;--cell-weight:400;--cell-spacing:.02em}`, used by `.grid .cell`. JSON tiles under `html[data-json="cell"] pre.json` use `--cell-font`, 16px, weight 400 everywhere (no bold), letter-spacing .07em, word-spacing .08em, line-height 1.95.
  - Classic: the original JSON tile look, unchanged.
- Sizes: body 18px, line-height 1.7; code 16px, line-height 1.8; tables 16px, table headers 17px. SVG diagrams as displayed: box titles about 22px, subtitles 16-17px, arrow labels 16-18px bold. Never below 14px.
- Bold text is never small: legend labels 15px, pills / badges / chips / status tags 15-16px with roomy padding (the grid's mini pills and the RECOMMENDED tag included; the tag is dark text on green, never white), buttons 16px bold, tile headings 19-22px.
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
- Screenshots: `scripts/shoot.sh` shoots the three backgrounds at a bounded height and crops 2000px slices. Look at crops only, never the full raster.


## Colors (same meaning everywhere)

- Code blocks: soft navy background (#1b2232) in every background. Plain words (variables, punctuation) soft blue-gray (#c9d3e8), never white. Keywords hot pink bold (#ff4fa3), type names light blue regular weight (#6cc9ee, not bold), method calls yellow (#ffd84a), strings green (#7dff7a), numbers and arrows orange (#ffa04a), comments lavender (#c9b8ff). Added and changed lines are marked concisely, diff style, never as a solid block: a `+` in the gutter, a 4px left bar and a faint tint (13-15%) in the line's color, yellow #ffe95c for added and orange #ffb347 for changed, with the token colors unchanged. Color code tokens automatically with a small tokenizer script. Show a code color key and the two line marks in the legend.
- Text tiles (cards, build steps, decisions, opportunities, roadmap phases): colored BORDER only. A 2px border in the tile's color and an 8px left edge in the same color. The inside uses the background's tile color with normal ink text and headings: no tinted background, no colored heading. Cycle a bright palette (pink #ff4fa3, blue #2bb3e8, gold #f2b705, green #2fbf4a, orange #ff8a3d, purple #9b6bff) so neighbouring tiles differ, or color by meaning when the tiles have a category (module, kind, status).
- One color per module or external system (for example red, purple, green, orange, blue, brown, gray) for diagram boxes, arrows (color of the caller) and code-block edges.
- One color per command or use case, reused in result matrices and lifecycles.
- Build status colors: built green, next orange, increment 2 purple, increment 3 red.
- Links: one look everywhere, a pill (Lexend 15px bold, letter-spacing 0.03em, padding 4px 13px) with a 2px link-blue border #2bb3e8 on the tile color, text dark blue #065a86 in Lavender and Sand, #8fdcff in Dark, ending in ↗. Inside a link, lines added are green (#13802b; dark #7dff7a) and lines removed are red (#c0262d; dark #ff9a9a), both bold.
- Line-count pill: the Numbers peach, #ffdcb8 with #111 text (dark: #6b3d12 with #ffe9d2), same size as the link pills.
- A legend at the top lists all of these, including a "Links" row: a sample line-count pill ("lines in the file"), "View file ↗", and "View changes +14 −19 ↗" ("added · removed in this PR").

- The "New and modified in this PR" grid: `150px repeat(n, minmax(0,1fr))` and `overflow-wrap:anywhere` on `.grid .cell`, so five modules fit the 1300px page and a long file name wraps instead of widening its column.
- Tree boxes take their width from the longest name in the tree (12.5px a character plus 30, never under 230), so a long type name never runs past its box.
- Tiles are a wrapping flex row (`.tiles`, each tile 380px or wider): two tiles share a row, a tile left alone on its row fills it, and a tile that carries a code block spans the whole row (`.tile.wide`), so a statement is read, not scrolled. In a tile narrower than 640px the heading's pills (`.right`) drop to a row of their own under the title instead of wrapping one by one (a container query).
- Every SVG figure's viewBox is fitted to what was drawn (`fit()` in app.js): no empty band above or below a diagram. Four module or state boxes (210px, 100px gaps) fit the 1196px figure unscaled; a wider diagram may shrink to 87.5% at most (16px text stays at 14px) and scrolls inside its figure past that (`min-width` on the svg).
- Arc labels never sit on their line: a skip arc's label is above its apex (below it for a return arc), a between-rows S-curve's label is above its flat middle or right of it when the line is nearly vertical, a self-loop's label is above the loop on the top-left corner of the box; skip arcs leave from right of center, so the two never cross.
- The file path under a tile heading wraps anywhere (`.tile .path`) and is never highlighted; a narrow tile never clips it.
