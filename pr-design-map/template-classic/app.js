/* Classic renderer: the first design-map look (IBM Plex, light and dark, numbered sections, layered module
   columns, text trees, cards). Same data as the default template: map.json over files.json, embedded by
   build.sh as the JSON blocks #files-json and #map-json. */
(function () {
  'use strict';
  const embedded = id => { const el = document.getElementById(id); return el ? JSON.parse(el.textContent) : {}; };
  const isObj = v => v && typeof v === 'object' && !Array.isArray(v);
  const merge = (a, b) => { const out = { ...a }; for (const k in b) out[k] = isObj(a[k]) && isObj(b[k]) ? merge(a[k], b[k]) : b[k]; return out; };
  const M = window.MAP || merge(embedded('files-json'), embedded('map-json'));
  /* Named colors resolve to CSS variables, so the dark theme swaps every one of them; any other CSS color is used as is. */
  const NAMED = ['pink', 'blue', 'gold', 'green', 'orange', 'purple', 'red', 'brown', 'gray', 'teal'];
  const CYCLE = ['pink', 'blue', 'gold', 'green', 'orange', 'purple'];
  const color = (c, i) => NAMED.includes(c) ? `var(--c-${c})` : c || `var(--c-${CYCLE[(i || 0) % CYCLE.length]})`;
  const KIND = { record: 'teal', interface: 'pink', enum: 'gold', table: 'brown', helper: 'gray', util: 'gray', class: 'gray', aggregate: 'teal' };
  const kindColor = k => { const w = String(k || '').toLowerCase().split(/[^a-z]+/).find(x => KIND[x]); return w ? `var(--c-${KIND[w]})` : null; };
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const h = (tag, attrs, ...kids) => {
    const e = document.createElement(tag);
    for (const k in attrs || {}) { if (attrs[k] == null) continue; if (k === 'html') e.innerHTML = attrs[k]; else if (k === 'style') e.style.cssText = attrs[k]; else e.setAttribute(k, attrs[k]); }
    for (const k of kids.flat()) if (k != null) e.append(k.nodeType ? k : document.createTextNode(k));
    return e;
  };
  const col = (el, c) => { if (c) el.style.setProperty('--col', c); return el; };
  const slug = s => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

  /* ---------- theme: light or dark, the system preference by default ---------- */
  function initTheme() {
    let t = new URLSearchParams(location.search).get('theme'); if (t && t !== 'dark') t = 'light';
    try { t = t || localStorage.getItem('dm-classic-theme'); } catch (e) {}
    if (!t) t = window.matchMedia && matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    setTheme(t);
  }
  function setTheme(t) { document.documentElement.setAttribute('data-theme', t); try { localStorage.setItem('dm-classic-theme', t); } catch (e) {} const b = document.getElementById('themeBtn'); if (b) b.textContent = t === 'dark' ? 'Light mode' : 'Dark mode'; }

  /* ---------- links ---------- */
  const repo = () => `https://github.com/${M.pr.owner}/${M.pr.repo}`;
  const prUrl = () => M.pr.url || `${repo()}/pull/${M.pr.number}`;
  const fileUrl = f => `${repo()}/blob/${M.pr.head}/${f.path}`;
  const diffUrl = f => `${prUrl()}/files#diff-${f.anchor}`;
  const pill = (href, html) => h('a', { class: 'pill', href, target: '_blank', rel: 'noopener', html: html + ' ↗' });
  const delta = f => `<span class="add">+${f.added}</span> <span class="del">−${f.removed}</span>`;
  const countPill = f => h('span', { class: 'count' }, `${f.lines} lines`);
  const note = f => (M.notes && M.notes[f.path]) || {};
  const isNew = f => f.status === 'added';
  const isMod = f => f.status === 'modified' || f.status === 'renamed';
  const files = () => (M.files || []).filter(f => f.status !== 'deleted');
  const moduleOf = name => (M.modules || []).find(m => m.name === name);
  const moduleColor = name => { const i = (M.modules || []).findIndex(m => m.name === name); return i < 0 ? null : color(M.modules[i].color, i); };

  /* ---------- code ---------- */
  const KW = new Set('and as assert async await break case catch class const continue def default del do elif else enum except export extends final finally fn for from fun func function if impl import in interface is lambda let match mod new nil none not null object or override package pass private protected public pub raise return sealed self static struct super switch then this throw throws trait try type typeof use val var void when where while with yield yes no true false True False None'.split(' '));
  function tokenizeLine(line, lang) {
    const out = []; let i = 0; const n = line.length;
    const cmt = lang === 'python' || lang === 'ruby' || lang === 'sh' || lang === 'yaml' ? '#' : '//';
    while (i < n) {
      const rest = line.slice(i); let m;
      if (rest.startsWith(cmt) || rest.startsWith('/*') || (lang === 'sql' && rest.startsWith('--'))) { out.push(`<span class="cm">${esc(rest)}</span>`); break; }
      if ((m = rest.match(/^("""|'''|"|'|`)/))) { const q = m[1]; let j = rest.indexOf(q, q.length); if (j < 0) j = rest.length - q.length; const s = rest.slice(0, j + q.length); out.push(`<span class="st">${esc(s)}</span>`); i += s.length; continue; }
      if ((m = rest.match(/^\d+(\.\d+)?[a-zA-Z]*/))) { out.push(`<span class="nm">${esc(m[0])}</span>`); i += m[0].length; continue; }
      if ((m = rest.match(/^(->|=>|<-|::|\|>|>>=|&&|\|\|)/))) { out.push(`<span class="nm">${esc(m[0])}</span>`); i += m[0].length; continue; }
      if ((m = rest.match(/^[A-Za-z_][A-Za-z0-9_]*/))) {
        const w = m[0]; const after = rest.slice(w.length); let cls = '';
        if (KW.has(w)) cls = 'kw'; else if (/^[A-Z]/.test(w) && !/^[A-Z0-9_]+$/.test(w)) cls = 'ty'; else if (/^\s*\(/.test(after)) cls = 'fn';
        out.push(cls ? `<span class="${cls}">${esc(w)}</span>` : esc(w)); i += w.length; continue;
      }
      out.push(esc(rest[0])); i++;
    }
    return out.join('');
  }
  const line = (indent, html, cls) => `<span class="ln${cls ? ' ' + cls : ''}" style="--i:${indent}">${html || ' '}</span>`;
  const indentOf = l => { const m = l.match(/^[ \t]*/)[0]; return { n: m.replace(/\t/g, '    ').length, rest: l.slice(m.length) }; };
  function codeBlock(code, edge) {
    if (!code) return null;
    const lang = code.lang || '', added = new Set(code.added || []), changed = new Set(code.changed || []);
    const lines = String(code.text || '').replace(/\n$/, '').split('\n');
    const html = lines.map((l, i) => { const k = i + 1; const { n, rest } = indentOf(l); return line(n, tokenizeLine(rest, lang), added.has(k) ? 'added' : changed.has(k) ? 'changed' : ''); }).join('');
    return col(h('pre', { class: 'code' + (edge ? ' edge' : ''), html: `<code>${html}</code>` }), edge);
  }
  function jsonBlock(value, unknown, edge) {
    const unk = new Set(unknown || []); const out = [];
    const push = (ind, html, bad) => out.push(line(ind * 2, bad ? `<span class="unknown">${html}</span>` : html));
    const scalar = v => Array.isArray(v) ? '[]' : v && typeof v === 'object' ? '{}' : typeof v === 'string' ? `<span class="st">${esc(JSON.stringify(v))}</span>` : typeof v === 'number' ? `<span class="nm">${v}</span>` : `<span class="kw">${String(v)}</span>`;
    const emit = (v, path, ind, prefix, comma, bad) => {
      const arr = Array.isArray(v) && v.length, obj = !Array.isArray(v) && v && typeof v === 'object' && Object.keys(v).length;
      if (!arr && !obj) return push(ind, prefix + scalar(v) + comma, bad);
      push(ind, prefix + (arr ? '[' : '{'), bad);
      if (arr) v.forEach((x, i) => emit(x, `${path}[${i}]`, ind + 1, '', i < v.length - 1 ? ',' : '', bad));
      else Object.keys(v).forEach((k, i, keys) => { const p = path ? `${path}.${k}` : k; emit(v[k], p, ind + 1, `<span class="ty">${esc(JSON.stringify(k))}</span>: `, i < keys.length - 1 ? ',' : '', bad || unk.has(p)); });
      push(ind, (arr ? ']' : '}') + comma, bad);
    };
    emit(value, '', 0, '', '', false);
    return col(h('pre', { class: 'json' + (edge ? ' edge' : ''), html: `<code>${out.join('')}</code>` }), edge);
  }
  /* A type hierarchy as the first version drew it: a text tree with box-drawing lines, one per root. */
  function treeBlock(root) {
    const rows = [];
    const name = n => `<span class="ty">${esc(n.name)}</span>${n.sub ? `  <span class="cm">${esc(n.sub)}</span>` : ''}`;
    rows.push(`${root.children && root.children.length ? '<span class="kw">sealed</span> ' : ''}${name(root)}`);
    const walk = (n, prefix) => (n.children || []).forEach((c, i, all) => { const last = i === all.length - 1; rows.push(`${esc(prefix)}${last ? '└── ' : '├── '}${name(c)}`); walk(c, prefix + (last ? '    ' : '│   ')); });
    walk(root, '');
    return col(h('pre', { class: 'tree edge', html: `<code>${rows.map(r => line(0, r)).join('')}</code>` }), root.color ? color(root.color) : null);
  }

  /* ---------- prose highlights: key words bold, names in the mono face ---------- */
  const HL = /\*\*(.+?)\*\*|\b([A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+)\b|\b([A-Z][A-Z0-9_]{2,})\b/g;
  const SKIP = 'pre,code,a,h1,h2,h3,.pill,.chip,.kchip,.count,.legend,.tag,nav,.meta,svg,.pkg,.card-head';
  function highlightProse(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, { acceptNode: n => n.parentElement.closest(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT });
    const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const n of nodes) {
      const t = n.nodeValue; if (!HL.test(t)) { HL.lastIndex = 0; continue; } HL.lastIndex = 0;
      n.replaceWith(h('span', { html: esc(t).replace(HL, (m, key, type, cst) => key ? `<span class="hl-key">${key}</span>` : type ? `<span class="hl-type">${type}</span>` : `<span class="hl-const">${cst}</span>`) }));
    }
  }

  /* ---------- SVG ---------- */
  const NS = 'http://www.w3.org/2000/svg';
  const sv = (tag, attrs, text) => { const e = document.createElementNS(NS, tag); for (const k in attrs || {}) if (attrs[k] != null) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; return e; };
  /* Arrow heads take their color from the line: every colored element carries style="color:…" and draws with currentColor. */
  const tinted = (el, c) => { if (c) el.setAttribute('style', `color:${c}`); return el; };
  function svgRoot() { const s = sv('svg'); const d = sv('defs'); d.innerHTML = `<marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="context-stroke"/></marker>`; s.append(d); return s; }
  function fit(svg, w, y0, y1) { const hgt = Math.round(y1 - y0); svg.setAttribute('viewBox', `0 ${Math.round(y0)} ${w} ${hgt}`); svg.setAttribute('width', w); svg.setAttribute('height', hgt); svg.style.aspectRatio = `${w} / ${hgt}`; svg.style.minWidth = `${Math.round(w * 0.875)}px`; }
  const arrow = (svg, d, c, dashed, width) => svg.append(tinted(sv('path', { d, fill: 'none', stroke: 'currentColor', 'stroke-width': width || 2.5, 'marker-end': 'url(#ah)', 'stroke-dasharray': dashed ? '5 4' : null }), c));
  function text(svg, x, y, str, cls, c, anchor) { const t = tinted(sv('text', { x, y, 'text-anchor': anchor || 'middle', class: cls }, str), c); svg.append(t); return t; }
  /* A labelled box: tinted fill, the title in the box's color, the subtitle in ink. */
  function box(svg, x, y, w, hgt, title, sub, c, rx) {
    const g = tinted(sv('g'), c);
    g.append(sv('rect', { x, y, width: w, height: hgt, rx: rx || 6, fill: 'currentColor', 'fill-opacity': 0.14, stroke: 'currentColor', 'stroke-width': 2 }));
    g.append(sv('text', { x: x + w / 2, y: y + (sub ? hgt / 2 - 2 : hgt / 2 + 5), 'text-anchor': 'middle', class: 'title' }, title));
    svg.append(g);
    if (sub) text(svg, x + w / 2, y + hgt / 2 + 14, sub, 'sub');
  }
  /* Fallback for engines without context-stroke: one marker per color actually used. */
  function fixMarkers(svg) {
    if (CSS.supports && CSS.supports('fill', 'context-stroke')) return;
    const defs = svg.querySelector('defs'); let n = 0;
    svg.querySelectorAll('path[marker-end]').forEach(p => { const c = p.getAttribute('style') || ''; const id = `ah-${n++}`; const m = sv('marker', { id, viewBox: '0 0 10 10', refX: 9, refY: 5, markerWidth: 7, markerHeight: 7, orient: 'auto' }); m.append(tinted(sv('path', { d: 'M0,0 L10,5 L0,10 z', fill: 'currentColor' }), c.replace('color:', ''))); defs.append(m); p.setAttribute('marker-end', `url(#${id})`); });
  }

  /* One text end to end: actor boxes over dashed lanes, numbered arrows in the caller's color, the value under each. */
  function sequenceDiagram(s) {
    const actors = s.actors || [], steps = s.steps || [];
    const LW = 140, GAP = 40, TOP = 112, STEP = 58, BOX = 44;
    const width = actors.length * (LW + GAP) - GAP + 40, bottom = TOP + Math.max(steps.length - 1, 0) * STEP + 36;
    const svg = svgRoot(); const cx = {}, cc = {};
    actors.forEach((a, i) => { const x = 20 + i * (LW + GAP); const c = color(a.color, i); cx[a.name] = x + LW / 2; cc[a.name] = c; box(svg, x, 14, LW, BOX, a.name, a.sub, c); svg.append(tinted(sv('line', { x1: x + LW / 2, y1: 14 + BOX, x2: x + LW / 2, y2: bottom, stroke: 'currentColor', 'stroke-width': 1.5, 'stroke-dasharray': '3 4', opacity: 0.7 }), c)); });
    steps.forEach((st, i) => {
      const x1 = cx[st.from], x2 = cx[st.to]; if (x1 == null || x2 == null) return;
      const y = TOP + i * STEP, c = cc[st.from], dir = x2 > x1 ? 1 : -1;
      arrow(svg, `M${x1},${y} L${x2 - dir * 2},${y}`, c, st.reply);
      const mx = (x1 + x2) / 2;
      const t = text(svg, mx, y - 8, '', 'arrow halo'); t.append(tinted(sv('tspan', { class: 'n' }, `${i + 1}  `), c), sv('tspan', {}, st.label || ''));
      if (st.value) text(svg, mx, y + 16, st.value, 'value halo');
    });
    fit(svg, width, 0, bottom + 12); fixMarkers(svg);
    return svg;
  }

  /* Modules and layers: one column per module, one row per layer, the PR's files in their cells, cross-module arrows above. */
  function layersDiagram(edges) {
    const mods = M.modules || [], layers = M.layers || [];
    // columns share the 1024px figure: 260px for up to three modules, narrower for more, never under 170 (then the figure scrolls)
    const GAP = mods.length <= 3 ? 80 : 50, CW = Math.max(170, Math.min(260, Math.floor((1000 - GAP * (mods.length - 1) - 40) / Math.max(mods.length, 1)))), HEAD = 34, LH = 17, PAD = 26;
    const cellFiles = (m, l) => files().filter(f => note(f).module === m.name && note(f).layer === l);
    const rowH = layers.map(l => PAD + LH * Math.max(1, ...mods.map(m => cellFiles(m, l).length)));
    const colH = HEAD + rowH.reduce((a, b) => a + b, 0);
    const width = mods.length * (CW + GAP) - GAP + 40;
    const used = {}; let top = 40;
    const svg = svgRoot();
    const xOf = i => 20 + i * (CW + GAP);
    mods.forEach((m, i) => {
      const x = xOf(i), c = color(m.color, i);
      svg.append(tinted(sv('rect', { x, y: 40, width: CW, height: colH, rx: 8, fill: 'currentColor', 'fill-opacity': 0.08, stroke: 'currentColor', 'stroke-width': 2.5 }), c));
      text(svg, x + CW / 2, 62, m.name, 'title', c);
      let y = 40 + HEAD;
      layers.forEach((l, j) => {
        svg.append(sv('line', { x1: x, x2: x + CW, y1: y, y2: y, stroke: 'currentColor', opacity: 0.35 }));
        text(svg, x + 12, y + 16, String(l).toUpperCase(), 'layer', null, 'start');
        const fs = cellFiles(m, l);
        if (!fs.length) text(svg, x + 12, y + 34, 'no change', 'cell', 'var(--muted)', 'start');
        fs.forEach((f, k) => { const n = note(f); const mark = isNew(f) ? '+ ' : isMod(f) ? '✎ ' : ''; text(svg, x + 12, y + 34 + k * LH, `${mark}${n.class || f.path.split('/').pop()}`, 'cell', null, 'start').append(sv('title', {}, f.path)); });
        y += rowH[j];
      });
    });
    (edges || []).forEach(e => {
      const a = mods.findIndex(m => m.name === e.from), b = mods.findIndex(m => m.name === e.to); if (a < 0 || b < 0) return;
      const c = color(mods[a].color, a), key = a < b ? `${a}-${b}` : `${b}-${a}`; used[key] = (used[key] || 0) + 1;
      const x1 = xOf(a) + CW / 2 + (a < b ? 40 : -40), x2 = xOf(b) + CW / 2 + (a < b ? -40 : 40);
      if (a === b) { arrow(svg, `M${x1 - 60},40 C${x1 - 60},-10 ${x1},-10 ${x1},40`, c); text(svg, x1 - 30, 4, e.label || '', 'arrow halo'); top = Math.min(top, -14); return; }
      const lift = 30 + 26 * used[key];
      arrow(svg, `M${x1},40 C${x1},${40 - lift} ${x2},${40 - lift} ${x2},40`, c);
      if (e.label) text(svg, (x1 + x2) / 2, 40 - lift * 0.75 - 6, e.label, 'arrow halo');
      top = Math.min(top, 40 - lift - 16);
    });
    text(svg, 20, 40 + colH + 22, 'Dependencies point down a column (application → domain ← infrastructure) and across modules only into api.', 'note', null, 'start');
    fit(svg, Math.max(width, 700), top - 6, 40 + colH + 34); fixMarkers(svg);
    return svg;
  }

  /* Lifecycle: pill-shaped states in a row, straight arrows between neighbours, arcs over or under the others, in the source's color. */
  function lifecycleDiagram(states, transitions) {
    const W = 180, H = 60, GAP = 110, perRow = Math.min(states.length, 4), rows = Math.ceil(states.length / perRow), ROWH = 220;
    const width = perRow * W + (perRow - 1) * GAP + 40;
    const svg = svgRoot(); const pos = {}; let top = 90, bottom = 90 + (rows - 1) * ROWH + H;
    states.forEach((st, i) => { const r = Math.floor(i / perRow), c = i % perRow; const x = 20 + c * (W + GAP), y = 90 + r * ROWH; pos[st.name] = { x, y, i, row: r, c: color(st.color, i) }; const g = tinted(sv('g'), pos[st.name].c); g.append(sv('rect', { x, y, width: W, height: H, rx: 30, fill: 'currentColor', 'fill-opacity': 0.16, stroke: 'currentColor', 'stroke-width': 3 }), sv('text', { x: x + W / 2, y: y + H / 2 + 6, 'text-anchor': 'middle', class: 'state' }, st.name)); svg.append(g); });
    const used = {};
    (transitions || []).forEach(t => {
      const a = pos[t.from], b = pos[t.to]; if (!a || !b) return;
      const key = a.i < b.i ? `${a.i}-${b.i}` : `${b.i}-${a.i}`; used[key] = (used[key] || 0) + 1;
      const forward = a.i < b.i, sameRow = a.row === b.row, adjacent = sameRow && Math.abs(a.i - b.i) === 1;
      let d, lx, ly, anchor;
      if (adjacent) { const y = a.y + H / 2 + (forward ? -10 : 10); const x1 = forward ? a.x + W : a.x, x2 = forward ? b.x : b.x + W; d = `M${x1},${y} L${x2},${y}`; lx = (x1 + x2) / 2; ly = y + (forward ? -10 : 22); }
      else if (a === b) { d = `M${a.x + 30},${a.y} C${a.x + 30},${a.y - 60} ${a.x + 90},${a.y - 60} ${a.x + 90},${a.y}`; lx = a.x + 10; ly = a.y - 66; anchor = 'start'; top = Math.min(top, ly - 18); }
      else if (!sameRow) { const down = a.row < b.row; const ya = down ? a.y + H : a.y, yb = down ? b.y : b.y + H; const x1 = a.x + W / 2, x2 = b.x + W / 2, ym = (ya + yb) / 2; d = `M${x1},${ya} C${x1},${ym} ${x2},${ym} ${x2},${yb}`; if (Math.abs(x1 - x2) < 80) { lx = Math.max(x1, x2) + 12; ly = ym + 6; anchor = 'start'; } else { lx = (x1 + x2) / 2; ly = ym - 10; } }
      else { const up = forward; const y0 = up ? a.y : a.y + H; const lift = (up ? -1 : 1) * (40 + 22 * used[key]); const apex = y0 + lift * 0.75; const x1 = a.x + W / 2 + (forward ? 30 : -30), x2 = b.x + W / 2 + (forward ? -30 : 30); d = `M${x1},${y0} C${x1},${y0 + lift} ${x2},${y0 + lift} ${x2},${up ? b.y : b.y + H}`; lx = (x1 + x2) / 2; if (up) { ly = apex - 10; top = Math.min(top, ly - 20); } else { ly = apex + 22; bottom = Math.max(bottom, ly + 8); } }
      arrow(svg, d, a.c, false, 3);
      if (t.label) { const tx = text(svg, lx, ly, t.label, 'arrow halo', a.c); if (anchor) tx.setAttribute('text-anchor', anchor); }
    });
    fit(svg, width, top - 24, bottom + 24); fixMarkers(svg);
    return svg;
  }


  /* ---------- components ---------- */
  const fig = svg => h('figure', {}, h('div', { class: 'scroll' }, svg));
  function table(t) {
    const colors = (t.colors || []).map((c, i) => color(c, i));
    const tb = h('table');
    if (t.columns) tb.append(h('thead', {}, h('tr', {}, t.columns.map((c, j) => col(h('th', { class: colors[j] ? 'col' : null }, c), colors[j])))));
    tb.append(h('tbody', {}, (t.rows || []).map(r => h('tr', {}, r.map((c, j) => {
      const yes = c === '✓' || c === 'yes', no = c === '✗' || c === 'no';
      return col(h('td', { class: yes ? 'yes' : no ? 'no' : null }, yes ? '●' : no ? '·' : String(c)), colors[j]);
    })))));
    return h('div', { class: 'table-wrap' }, tb);
  }
  /* A card: heading in the card's color, a kind chip, the lines, then code or JSON. Kinds color themselves. */
  function card(t, i, extra) {
    const c = kindColor(t.chip) || color(t.color, i);
    const el = col(h('div', { class: 'card' + (t.code ? ' wide' : '') }), c);
    const head = h('div', { class: 'card-head' }, h('h3', {}, t.title || ''));
    if (t.recommended) head.append(h('span', { class: 'chip tag' }, 'RECOMMENDED'));
    if (t.chip) head.append(h('span', { class: 'kchip' }, t.chip));
    (extra && extra.chips || []).forEach(x => head.append(x));
    el.append(head);
    if (extra && extra.sub) el.append(h('span', { class: 'pkg' }, extra.sub));
    if (t.lines) el.append(h('ul', {}, t.lines.map(l => h('li', {}, l))));
    if (t.text) el.append(h('p', {}, t.text));
    if (t.code) el.append(codeBlock(t.code, c));
    if (t.json) el.append(jsonBlock(t.json, t.unknown, c));
    if (extra && extra.links) el.append(h('div', { class: 'links' }, extra.links));
    return el;
  }
  function fileCard(f, i) {
    const n = note(f); const mod = moduleOf(n.module);
    const chips = [];
    if (isNew(f)) chips.push(h('span', { class: 'chip new' }, 'NEW')); else if (isMod(f)) chips.push(h('span', { class: 'chip mod' }, '✎ modified'));
    if (n.layer) chips.push(h('span', { class: 'chip' }, n.layer));
    const links = [countPill(f), pill(fileUrl(f), 'View file')]; if (isNew(f) || isMod(f)) links.push(pill(diffUrl(f), `View changes ${delta(f)}`));
    const t = { title: n.class || f.path.split('/').pop(), chip: n.kind, lines: n.lines, text: !n.lines ? n.change : null, code: n.code, color: mod && mod.color };
    const el = card(t, i, { chips, sub: f.path, links });
    if (!kindColor(n.kind)) col(el, moduleColor(n.module) || color(null, i));
    return el;
  }
  function groupedFileCards() {
    const mods = M.modules || [], layers = M.layers || []; const out = []; let i = 0; const seen = new Set();
    mods.forEach((m, mi) => layers.forEach(layer => {
      const fs = files().filter(f => note(f).module === m.name && note(f).layer === layer && note(f).kind !== 'table');
      if (!fs.length) return; fs.forEach(f => seen.add(f.path));
      out.push(h('div', { class: 'group-title' }, col(h('h3', {}, `${m.name} ${layer}`), color(m.color, mi)), h('span', { class: 'pkg' }, `${fs.length} file${fs.length > 1 ? 's' : ''}`)), h('div', { class: 'cards' }, fs.map(f => fileCard(f, i++))));
    }));
    const rest = files().filter(f => !seen.has(f.path) && note(f).kind !== 'table');
    if (rest.length) out.push(h('div', { class: 'group-title' }, h('h3', {}, 'Other files')), h('div', { class: 'cards' }, rest.map(f => fileCard(f, i++))));
    const tables = files().filter(f => note(f).kind === 'table');
    if (tables.length) out.push(h('div', { class: 'group-title' }, h('h3', {}, 'Database tables'), h('span', { class: 'pkg' }, 'tables and migrations')), h('div', { class: 'cards' }, tables.map(f => fileCard(f, i++))));
    return out;
  }
  const steps = (items, stack, render) => h('div', { class: 'three' + (stack ? ' stack' : '') }, items.map((it, i) => { const c = color(it.color, i); return h('div', { class: 'step' }, it.tag ? col(h('span', { class: 'tag' }, it.tag), c) : null, it.title ? h('h3', {}, it.title) : null, render(it, c, i)); }));
  const RENDER = {
    sequence: s => [fig(sequenceDiagram(s)), s.table ? table(s.table) : null],
    json: s => steps(s.items || [], s.stack, (it, c) => [it.lines ? h('ul', {}, it.lines.map(l => h('li', {}, l))) : null, jsonBlock(it.value, it.unknown, c)]),
    modules: s => [fig(layersDiagram(s.edges)), s.table ? [h('h3', {}, 'Who talks to whom'), table(s.table)] : null],
    tree: s => steps(s.roots || [], s.stack, r => treeBlock(r)),
    table: s => table(s),
    tiles: s => h('div', { class: 'cards' + (s.stack ? ' stack' : '') }, (s.items || []).map((t, i) => card(t, i))),
    code: s => codeBlock(s.code, s.edge ? color(s.edge) : null),
    'file-tiles': () => groupedFileCards(),
    lifecycle: s => fig(lifecycleDiagram((s.states || []).map((st, i) => typeof st === 'string' ? { name: st, color: CYCLE[i % CYCLE.length] } : st), s.transitions)),
    proposal: s => [
      h('div', { class: 'group-title' }, h('h3', {}, 'Current')), h('div', { class: 'cards stack' }, card({ ...s.current, color: s.current.color || 'gray' }, 0)),
      ...(s.options || []).map((o, i) => [h('div', { class: 'group-title' }, h('h3', {}, `Option: ${o.title}`)), h('div', { class: 'cards stack' }, card(o, i + 1))]).flat(),
      s.comparison ? table(s.comparison) : null,
      s.decisions ? [h('div', { class: 'group-title' }, h('h3', {}, 'Decisions')), h('div', { class: 'cards' }, s.decisions.map((d, i) => card(d, i)))] : null,
    ],
  };
  function section(s, i) {
    const id = s.id || slug(s.title || `section-${i}`);
    const wrap = h('section', { id, 'data-files': (s.files || []).join(',') });
    wrap.append(h('h2', { 'data-n': i + 1 }, s.title || ''));
    const R = RENDER[s.type]; if (R) wrap.append(...[R(s)].flat(2).filter(Boolean)); else wrap.append(h('p', { class: 'muted' }, `unknown section type ${s.type}`));
    return wrap;
  }

  /* ---------- header: title, facts, theme button, legend, numbered nav ---------- */
  function header() {
    const fs = M.files || []; const added = fs.reduce((a, f) => a + (f.added || 0), 0), removed = fs.reduce((a, f) => a + (f.removed || 0), 0);
    const el = h('header');
    el.append(h('h1', {}, `${M.app} Design Map: PR #${M.pr.number}`));
    const meta = h('p', { class: 'meta' }, pill(prUrl(), `PR #${M.pr.number}`), '·', h('span', {}, M.pr.branch), '·', h('span', { class: 'sha' }, String(M.pr.head).slice(0, 7)), '·', h('span', {}, M.pr.date), '·', h('span', { html: `${fs.length} files <span class="add">+${added}</span> <span class="del">−${removed}</span>` }), '·', h('span', {}, `Updated ${M.updated || ''}`));
    if (M.session && M.session.url) meta.append('·', pill(M.session.url, M.session.name || `session ${String(M.session.id || '').slice(0, 8)}`));
    el.append(meta, brief());
    const btn = h('button', { class: 'theme-btn', id: 'themeBtn', type: 'button' }, 'Dark mode'); btn.onclick = () => setTheme(document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark'); el.append(btn);
    el.append(legend());
    el.append(h('nav', { 'aria-label': 'Sections' }, h('ol', {}, (M.sections || []).map((s, i) => h('li', {}, h('a', { href: '#' + (s.id || slug(s.title || `section-${i}`)) }, s.title))))));
    return el;
  }
  /* "What changed": the map's short summary (a few bullets) under the PR facts; its header button folds it, open at first; nothing when the map has none */
  function brief() {
    const items = [].concat(M.summary || []).filter(Boolean); if (!items.length) return null;
    const act = h('span', { class: 'act' }, 'Hide ▴');
    const btn = h('button', { type: 'button', class: 'brief-btn', 'aria-expanded': 'true' }, h('span', {}, 'What changed'), act);
    const el = h('div', { class: 'brief open' }, btn, h('ul', {}, items.map(t => h('li', {}, t))));
    btn.onclick = () => { const open = el.classList.toggle('open'); btn.setAttribute('aria-expanded', String(open)); act.textContent = open ? 'Hide ▴' : 'Show ▾'; };
    return el;
  }
  function legend() {
    const sw = (name, c) => col(h('span', { class: 'sw' }, name), c);
    const kchip = (name, c) => col(h('span', { class: 'kchip' }, name), c);
    const sample = { path: 'x', anchor: '', added: 14, removed: 19, lines: 135 };
    const rows = [
      ['Modules', (M.modules || []).map((m, i) => sw(m.name, color(m.color, i)))],
      ['Card kinds', Object.entries({ record: 'teal', interface: 'pink', enum: 'gold', 'helper / class': 'gray', 'DB table': 'brown' }).map(([k, c]) => kchip(k, `var(--c-${c})`))],
      ['Files', [h('span', { class: 'chip new' }, 'NEW'), h('span', { class: 'chip mod' }, '✎ modified'), h('span', { class: 'muted' }, 'in code:'), h('pre', { class: 'code', style: 'padding:2px 8px;font-size:12px', html: '<code><span class="ln added" style="--i:0">added line</span><span class="ln changed" style="--i:0">changed line</span></code>' })]],
      ['JSON', [h('code', { html: '<span style="color:var(--j-key)">"key"</span>' }), h('code', { html: '<span style="color:var(--j-str)">"text"</span>' }), h('code', { html: '<span style="color:var(--j-num)">42</span>' }), h('code', { html: '<span style="color:var(--j-null);font-style:italic">null</span>' }), h('code', { html: '<span style="color:var(--j-bad);font-weight:600">"unknown key"</span>' }), h('code', { html: '<span style="color:var(--c-teal);font-weight:600">TypeName</span>' })]],
      ['Links', [countPill(sample), h('span', { class: 'muted' }, 'lines in the file'), h('span', { class: 'pill', html: 'View file ↗' }), h('span', { class: 'pill', html: `View changes ${delta(sample)} ↗` }), h('span', { class: 'muted' }, 'added · removed in this PR')]],
    ];
    if (M.legend) for (const k in M.legend) rows.push([k, M.legend[k].map((e, i) => sw(e.name, color(e.color, i)))]);
    const el = h('div', { class: 'legend' });
    rows.forEach(([k, v]) => el.append(h('div', { class: 'row' }, h('span', { class: 'lbl' }, k), v)));
    return el;
  }

  /* ---------- main ---------- */
  function main() {
    const root = document.getElementById('map'); root.innerHTML = '';
    document.documentElement.setAttribute('data-app', M.app || ''); document.documentElement.setAttribute('data-pr', M.pr.number); document.documentElement.setAttribute('data-head', M.pr.head);
    document.title = `${M.app} Design Map: PR #${M.pr.number}`;
    root.append(header(), ...(M.sections || []).map(section));
    highlightProse(root); initTheme();
  }
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', main) : main();
})();
