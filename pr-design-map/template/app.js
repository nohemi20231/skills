/* PR design map renderer. Reads window.MAP (data.js) and builds the page.
   The agent writes map.json; scripts/pr-files.sh writes files.json; build.sh merges them into data.js. */
(function () {
  'use strict';
  const M = window.MAP || {};
  const COLORS = { pink: '#ff4fa3', blue: '#2bb3e8', gold: '#f2b705', green: '#2fbf4a', orange: '#ff8a3d', purple: '#9b6bff', red: '#e0383e', brown: '#a0683a', gray: '#7a7f8c' };
  const CYCLE = ['pink', 'blue', 'gold', 'green', 'orange', 'purple'];
  const color = (c, i) => COLORS[c] || c || COLORS[CYCLE[(i || 0) % CYCLE.length]];
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  const h = (tag, attrs, ...kids) => {
    const e = document.createElement(tag);
    for (const k in attrs || {}) { if (attrs[k] == null) continue; if (k === 'html') e.innerHTML = attrs[k]; else if (k === 'style') e.style.cssText = attrs[k]; else e.setAttribute(k, attrs[k]); }
    for (const k of kids.flat()) if (k != null) e.append(k.nodeType ? k : document.createTextNode(k));
    return e;
  };
  const slug = s => String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');

  /* ---------- theme ---------- */
  function initTheme() {
    const q = new URLSearchParams(location.search);
    let t = q.get('theme'); if (t === 'light') t = 'lavender';
    let j = q.get('json');
    try { t = t || localStorage.getItem('dm-theme') || 'lavender'; j = j || localStorage.getItem('dm-json') || 'cell'; } catch (e) { t = t || 'lavender'; j = j || 'cell'; }
    setTheme(t); setJson(j);
  }
  function setTheme(t) { document.documentElement.setAttribute('data-theme', t); try { localStorage.setItem('dm-theme', t); } catch (e) {} document.querySelectorAll('[data-set-theme]').forEach(b => b.setAttribute('aria-pressed', b.dataset.setTheme === t)); }
  function setJson(j) { document.documentElement.setAttribute('data-json', j); try { localStorage.setItem('dm-json', j); } catch (e) {} document.querySelectorAll('[data-set-json]').forEach(b => b.setAttribute('aria-pressed', b.dataset.setJson === j)); }

  /* ---------- links ---------- */
  const repo = () => `https://github.com/${M.pr.owner}/${M.pr.repo}`;
  const prUrl = () => M.pr.url || `${repo()}/pull/${M.pr.number}`;
  const fileUrl = f => `${repo()}/blob/${M.pr.head}/${f.path}`;
  const diffUrl = f => `${prUrl()}/files#diff-${f.anchor}`;
  const pill = (href, html) => h('a', { class: 'pill', href, target: '_blank', rel: 'noopener', html: html + ' ↗' });
  const delta = f => `<span class="add">+${f.added}</span> <span class="del">−${f.removed}</span>`;
  const countPill = f => h('span', { class: 'count' }, `${f.lines} lines`);
  const changesPill = f => pill(diffUrl(f), `View changes ${delta(f)}`);
  const miniPill = f => pill(diffUrl(f), delta(f));
  const note = f => (M.notes && M.notes[f.path]) || {};
  const isNew = f => f.status === 'added';
  const isMod = f => f.status === 'modified' || f.status === 'renamed';
  const files = () => (M.files || []).filter(f => f.status !== 'deleted');

  /* ---------- code ---------- */
  const KW = new Set('and as assert async await break case catch class const continue def default del do elif else enum except export extends final finally fn for from fun func function if impl import in interface is lambda let match mod new nil none not null object or override package pass private protected public pub raise return self static struct super switch then this throw throws trait try type typeof use val var void when where while with yield yes no true false True False None'.split(' '));
  function tokenizeLine(line, lang) {
    const out = []; let i = 0; const n = line.length;
    const cmt = lang === 'python' || lang === 'ruby' || lang === 'sh' || lang === 'yaml' ? '#' : '//';
    while (i < n) {
      const rest = line.slice(i);
      let m;
      if (rest.startsWith(cmt) || rest.startsWith('/*') || (lang === 'sql' && rest.startsWith('--'))) { out.push(`<span class="cm">${esc(rest)}</span>`); break; }
      if ((m = rest.match(/^("""|'''|"|'|`)/))) { const q = m[1]; let j = rest.indexOf(q, q.length); if (j < 0) j = rest.length - q.length; const s = rest.slice(0, j + q.length); out.push(`<span class="st">${esc(s)}</span>`); i += s.length; continue; }
      if ((m = rest.match(/^\d+(\.\d+)?[a-zA-Z]*/))) { out.push(`<span class="nm">${esc(m[0])}</span>`); i += m[0].length; continue; }
      if ((m = rest.match(/^(->|=>|<-|::|\|>|>>=|&&|\|\|)/))) { out.push(`<span class="nm">${esc(m[0])}</span>`); i += m[0].length; continue; }
      if ((m = rest.match(/^[A-Za-z_][A-Za-z0-9_]*/))) {
        const w = m[0]; const after = rest.slice(w.length);
        let cls = '';
        if (KW.has(w)) cls = 'kw';
        else if (/^[A-Z]/.test(w) && !/^[A-Z0-9_]+$/.test(w)) cls = 'ty';
        else if (/^\s*\(/.test(after)) cls = 'fn';
        out.push(cls ? `<span class="${cls}">${esc(w)}</span>` : esc(w)); i += w.length; continue;
      }
      out.push(esc(rest[0])); i++;
    }
    return out.join('');
  }
  function codeBlock(code, edge) {
    if (!code) return null;
    const lang = code.lang || '';
    const added = new Set(code.added || []), changed = new Set(code.changed || []);
    const lines = String(code.text || '').replace(/\n$/, '').split('\n');
    const html = lines.map((l, i) => { const k = i + 1; const c = added.has(k) ? ' added' : changed.has(k) ? ' changed' : ''; return `<span class="ln${c}">${tokenizeLine(l, lang) || ' '}</span>`; }).join('');
    const pre = h('pre', { class: 'code', html: `<code>${html}</code>` });
    if (edge) pre.style.setProperty('--edge', color(edge));
    return pre;
  }
  function jsonBlock(value, unknown) {
    const unk = new Set(unknown || []);
    const render = (v, path, ind) => {
      const pad = '  '.repeat(ind);
      if (Array.isArray(v)) { if (!v.length) return '[]'; return '[\n' + v.map((x, i) => pad + '  ' + render(x, `${path}[${i}]`, ind + 1)).join(',\n') + '\n' + pad + ']'; }
      if (v && typeof v === 'object') {
        const keys = Object.keys(v); if (!keys.length) return '{}';
        return '{\n' + keys.map(k => { const p = path ? `${path}.${k}` : k; const body = `<span class="ty">"${esc(k)}"</span>: ${render(v[k], p, ind + 1)}`; return pad + '  ' + (unk.has(p) ? `<span class="unknown">${body}</span>` : body); }).join(',\n') + '\n' + pad + '}';
      }
      if (typeof v === 'string') return `<span class="st">"${esc(v)}"</span>`;
      if (typeof v === 'number') return `<span class="nm">${v}</span>`;
      return `<span class="kw">${String(v)}</span>`;
    };
    return h('pre', { class: 'json', html: `<code>${render(value, '', 0)}</code>` });
  }

  /* ---------- prose highlights ---------- */
  const HL = /\*\*(.+?)\*\*|\b([A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+)\b|\b([A-Z][A-Z0-9_]{2,})\b|\b([A-Z]{1,3}-[A-Z]?\d{1,4}[a-z]?|[VDOR]\d{1,4})\b|\b(\d+(?:\.\d+)?)\b/g;
  const SKIP = 'pre,code,a,h1,h2,h3,.pill,.chip,.count,.btn,.legend,.tag,.nav,.meta,.row,svg,.tile>h3';
  function highlightProse(root) {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, { acceptNode: n => n.parentElement.closest(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT });
    const nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
    for (const n of nodes) {
      const t = n.nodeValue; if (!HL.test(t)) { HL.lastIndex = 0; continue; } HL.lastIndex = 0;
      const html = esc(t).replace(HL, (m, key, type, cst, id, num) => key ? `<span class="hl hl-key">${key}</span>` : type ? `<span class="hl hl-type">${type}</span>` : cst ? `<span class="hl hl-const">${cst}</span>` : id ? `<span class="hl hl-id">${id}</span>` : `<span class="hl hl-num">${num}</span>`);
      const span = h('span', { html }); n.replaceWith(span);
    }
  }

  /* ---------- SVG helpers ---------- */
  const NS = 'http://www.w3.org/2000/svg';
  const sv = (tag, attrs, text) => { const e = document.createElementNS(NS, tag); for (const k in attrs || {}) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; return e; };
  function svgRoot(w, hgt) { const s = sv('svg', { viewBox: `0 0 ${w} ${hgt}`, width: w, height: hgt }); const d = sv('defs'); d.innerHTML = Object.entries(COLORS).map(([k, v]) => `<marker id="arr-${k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="${v}"/></marker>`).join(''); s.append(d); return s; }
  const markerFor = c => `url(#arr-${Object.keys(COLORS).find(k => COLORS[k] === c) || 'gray'})`;
  function label(svg, x, y, text, cls) { const t = sv('text', { x, y, 'text-anchor': 'middle', class: `halo ${cls || 'arrow'}` }, text); svg.append(t); return t; }
  function box(svg, x, y, w, hgt, title, sub, col) {
    svg.append(sv('rect', { x, y, width: w, height: hgt, rx: 12, class: 'box', stroke: col }));
    svg.append(sv('text', { x: x + w / 2, y: y + (sub ? hgt / 2 - 6 : hgt / 2 + 8), 'text-anchor': 'middle', class: 'title' }, title));
    if (sub) svg.append(sv('text', { x: x + w / 2, y: y + hgt / 2 + 20, 'text-anchor': 'middle', class: 'sub' }, sub));
  }

  /* boxes in a row with labelled arrows; used by modules and lifecycle diagrams */
  function boxesDiagram(nodes, edges) {
    const W = 220, H = 84, GAP = 130, perRow = Math.min(nodes.length, 4);
    const rows = Math.ceil(nodes.length / perRow), ROWH = 230;
    const width = perRow * W + (perRow - 1) * GAP + 40, height = 90 + (rows - 1) * ROWH + H + 50;
    const svg = svgRoot(width, height);
    const pos = {};
    nodes.forEach((n, i) => { const r = Math.floor(i / perRow), c = i % perRow; const x = 20 + c * (W + GAP), y = 90 + r * ROWH; pos[n.name] = { x, y, i, col: color(n.color, i) }; box(svg, x, y, W, H, n.name, n.sub, pos[n.name].col); });
    const used = {};
    (edges || []).forEach(e => {
      const a = pos[e.from], b = pos[e.to]; if (!a || !b) return;
      const col = a.col, key = a.i < b.i ? `${a.i}-${b.i}` : `${b.i}-${a.i}`; used[key] = (used[key] || 0) + 1;
      const forward = a.i < b.i, adjacent = Math.abs(a.i - b.i) === 1 && Math.floor(a.i / perRow) === Math.floor(b.i / perRow);
      let d, lx, ly;
      if (adjacent) { const y = a.y + H / 2 + (forward ? -12 : 12); const x1 = forward ? a.x + W : a.x, x2 = forward ? b.x : b.x + W; d = `M${x1},${y} L${x2},${y}`; lx = (x1 + x2) / 2; ly = y + (forward ? -10 : 24); }
      else if (a === b) { d = `M${a.x + W - 40},${a.y} C${a.x + W - 40},${a.y - 60} ${a.x + W + 30},${a.y - 60} ${a.x + W},${a.y + 20}`; lx = a.x + W; ly = a.y - 48; }
      else { const up = forward; const y0 = up ? a.y : a.y + H; const lift = (up ? -1 : 1) * (40 + 22 * used[key]); const x1 = a.x + W / 2 + (forward ? 30 : -30), x2 = b.x + W / 2 + (forward ? -30 : 30); d = `M${x1},${y0} C${x1},${y0 + lift} ${x2},${y0 + lift} ${x2},${up ? b.y : b.y + H}`; lx = (x1 + x2) / 2; ly = y0 + lift * 0.78 + (up ? 0 : 8); }
      svg.append(sv('path', { d, fill: 'none', stroke: col, 'stroke-width': 3, 'marker-end': markerFor(col) }));
      if (e.label) label(svg, lx, ly, e.label);
    });
    return svg;
  }

  function sequenceDiagram(s) {
    const actors = s.actors || [], steps = s.steps || [];
    const LW = 210, GAP = 60, TOP = 110, STEP = 96;
    const width = actors.length * (LW + GAP) + 20, height = TOP + steps.length * STEP + 40;
    const svg = svgRoot(width, height);
    const cx = {};
    actors.forEach((a, i) => { const x = 20 + i * (LW + GAP); const col = color(a.color, i); cx[a.name] = x + LW / 2; box(svg, x, 16, LW, 70, a.name, a.sub, col); svg.append(sv('line', { x1: x + LW / 2, y1: 86, x2: x + LW / 2, y2: height - 20, class: 'lane' })); cx['#' + a.name] = col; });
    steps.forEach((st, i) => {
      const x1 = cx[st.from], x2 = cx[st.to]; if (x1 == null || x2 == null) return;
      const y = TOP + i * STEP; const col = cx['#' + st.from]; const dir = x2 > x1 ? 1 : -1;
      svg.append(sv('line', { x1: x1 + dir * 4, y1: y, x2: x2 - dir * 12, y2: y, stroke: col, 'stroke-width': 3, 'marker-end': markerFor(col), 'stroke-dasharray': st.reply ? '8 6' : null }));
      const mx = (x1 + x2) / 2; label(svg, mx, y - 12, st.label || '');
      if (st.value) label(svg, mx, y + 28, st.value, 'sub');
    });
    return svg;
  }

  function treeDiagram(roots) {
    const W = 230, H = 56, DX = 290, DY = 74; let leaf = 0;
    const layout = (n, depth) => { n._d = depth; if (n.children && n.children.length) { n.children.forEach(c => layout(c, depth + 1)); n._y = (n.children[0]._y + n.children[n.children.length - 1]._y) / 2; } else n._y = leaf++ * DY; };
    roots.forEach(r => { layout(r, 0); leaf += 0.4; });
    let depth = 0; const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)); };
    roots.forEach(r => walk(r, n => { depth = Math.max(depth, n._d); }));
    const svg = svgRoot((depth + 1) * DX + 20, leaf * DY + 40);
    let i = 0;
    roots.forEach(r => walk(r, n => {
      const x = 20 + n._d * DX, y = 20 + n._y; const col = color(n.color, n._d);
      box(svg, x, y, W, H, n.name, n.sub, col); i++;
      (n.children || []).forEach(c => { const cy = 20 + c._y + H / 2; svg.append(sv('path', { d: `M${x + W},${y + H / 2} L${x + W + 30},${y + H / 2} L${x + W + 30},${cy} L${x + DX},${cy}`, fill: 'none', stroke: col, 'stroke-width': 3, 'marker-end': markerFor(col) })); });
    }));
    return svg;
  }

  /* ---------- components ---------- */
  function section(s, i) {
    const id = s.id || slug(s.title || `section-${i}`);
    const wrap = h('section', { id, 'data-files': (s.files || []).join(',') });
    wrap.append(h('h2', {}, s.title || ''));
    const R = RENDER[s.type]; if (R) wrap.append(...[R(s)].flat().filter(Boolean)); else wrap.append(h('p', { class: 'muted' }, `unknown section type ${s.type}`));
    return wrap;
  }
  const fig = svg => h('figure', {}, svg);
  function table(t) {
    const tb = h('table');
    if (t.columns) tb.append(h('thead', {}, h('tr', {}, t.columns.map(c => h('th', {}, c)))));
    tb.append(h('tbody', {}, (t.rows || []).map(r => h('tr', {}, r.map((c, j) => { const td = h('td', {}, String(c)); if (c === '✓' || c === 'yes') td.className = 'yes'; if (c === '✗' || c === 'no') td.className = 'no'; if (j === 0) td.style.fontWeight = '700'; return td; })))));
    return tb;
  }
  function tile(t, i) {
    const el = h('div', { class: 'tile' + (t.recommended ? ' recommended' : '') });
    el.style.setProperty('--tile-color', color(t.color, i));
    const head = h('h3', {}, t.title || '');
    if (t.recommended) head.append(h('span', { class: 'tag' }, 'RECOMMENDED'));
    if (t.chip) head.append(h('span', { class: 'chip' }, t.chip));
    el.append(head);
    if (t.lines) el.append(h('ul', {}, t.lines.map(l => h('li', {}, l))));
    if (t.code) el.append(codeBlock(t.code, t.color || CYCLE[i % CYCLE.length]));
    if (t.json) el.append(jsonBlock(t.json, t.unknown));
    return el;
  }
  function fileTile(f, i) {
    const n = note(f); const mod = (M.modules || []).find(m => m.name === n.module);
    const el = h('div', { class: 'tile' }); el.style.setProperty('--tile-color', color(mod && mod.color, i));
    const head = h('h3', {}, n.class || f.path.split('/').pop());
    if (isNew(f)) head.append(h('span', { class: 'chip new' }, 'NEW')); else if (isMod(f)) head.append(h('span', { class: 'chip mod' }, '✎ modified'));
    if (n.layer) head.append(h('span', { class: 'chip layer' }, n.layer));
    if (n.kind) head.append(h('span', { class: 'chip' }, n.kind));
    const right = h('span', { class: 'right' }, countPill(f), pill(fileUrl(f), 'View file'));
    if (isNew(f) || isMod(f)) right.append(changesPill(f));
    head.append(right); el.append(head);
    el.append(h('p', { class: 'muted', style: 'font:400 15px var(--font-mono);margin:0 0 8px' }, f.path));
    if (n.lines) el.append(h('ul', {}, n.lines.map(l => h('li', {}, l))));
    if (n.change && !n.lines) el.append(h('p', {}, n.change));
    if (n.code) el.append(codeBlock(n.code, mod && mod.color));
    return el;
  }
  function filesGrid() {
    const mods = M.modules || [], layers = M.layers || [];
    const g = h('div', { class: 'grid' }); g.style.gridTemplateColumns = `150px repeat(${mods.length}, 1fr)`;
    g.append(h('div'));
    mods.forEach((m, i) => { const d = h('div', { class: 'head' }, m.name); d.style.setProperty('--col', color(m.color, i)); g.append(d); });
    layers.forEach(layer => {
      g.append(h('div', { class: 'side' }, layer));
      mods.forEach((m, i) => {
        const fs = files().filter(f => note(f).module === m.name && note(f).layer === layer);
        const cell = h('div', { class: 'cell' + (fs.length ? '' : ' empty') }); cell.style.setProperty('--col', color(m.color, i));
        if (!fs.length) cell.append('no change');
        fs.forEach(f => { const n = note(f); const mark = isNew(f) ? '+ ' : isMod(f) ? '✎ ' : ''; cell.append(h('div', {}, `${mark}${f.path.split('/').pop()}${n.change ? ' · ' + n.change : ''}`, (isNew(f) || isMod(f)) ? miniPill(f) : null)); });
        g.append(cell);
      });
    });
    return g;
  }
  function groupedFileTiles() {
    const mods = M.modules || [], layers = M.layers || []; const out = []; let i = 0;
    const seen = new Set();
    mods.forEach(m => layers.forEach(layer => {
      const fs = files().filter(f => note(f).module === m.name && note(f).layer === layer && note(f).kind !== 'table');
      if (!fs.length) return; fs.forEach(f => seen.add(f.path));
      out.push(h('h3', {}, `${m.name} · ${layer}`), h('div', { class: 'tiles' }, fs.map(f => fileTile(f, i++))));
    }));
    const rest = files().filter(f => !seen.has(f.path) && note(f).kind !== 'table');
    if (rest.length) out.push(h('h3', {}, 'Other files'), h('div', { class: 'tiles' }, rest.map(f => fileTile(f, i++))));
    const tables = files().filter(f => note(f).kind === 'table');
    if (tables.length) out.push(h('h3', {}, 'Tables and migrations'), h('div', { class: 'tiles' }, tables.map(f => fileTile(f, i++))));
    return out;
  }
  const RENDER = {
    sequence: s => [fig(sequenceDiagram(s)), s.table ? table(s.table) : null],
    json: s => h('div', { class: 'tiles' + (s.stack ? ' stack' : '') }, (s.items || []).map((it, i) => tile({ title: it.title, json: it.value, unknown: it.unknown, lines: it.lines, color: it.color }, i))),
    modules: s => [fig(boxesDiagram(M.modules || [], s.edges)), s.table ? table(s.table) : null, h('h3', {}, 'New and modified in this PR'), filesGrid()],
    tree: s => fig(treeDiagram(s.roots || [])),
    table: s => table(s),
    tiles: s => h('div', { class: 'tiles' + (s.stack ? ' stack' : '') }, (s.items || []).map(tile)),
    code: s => codeBlock(s.code, s.edge),
    'file-tiles': () => groupedFileTiles(),
    lifecycle: s => fig(boxesDiagram((s.states || []).map((st, i) => typeof st === 'string' ? { name: st, color: CYCLE[i % CYCLE.length] } : st), s.transitions)),
    proposal: s => [
      h('h3', {}, 'CURRENT'), h('div', { class: 'tiles stack' }, tile({ ...s.current, color: s.current.color || 'gray' }, 0)),
      ...(s.options || []).map((o, i) => [h('h3', {}, `MODIFIED · ${o.title}`), h('div', { class: 'tiles stack' }, tile({ ...o, title: o.title }, i + 1))]).flat(),
      s.comparison ? table(s.comparison) : null,
      s.decisions ? h('div', { class: 'tiles' }, s.decisions.map(tile)) : null,
    ],
  };

  /* ---------- header, legend, nav ---------- */
  function header() {
    const fs = M.files || []; const added = fs.reduce((a, f) => a + (f.added || 0), 0), removed = fs.reduce((a, f) => a + (f.removed || 0), 0);
    const el = h('header');
    el.append(h('h1', {}, `${M.app} Design Map: PR #${M.pr.number}`));
    const meta = h('div', { class: 'meta' }, pill(prUrl(), `PR #${M.pr.number}`), h('span', {}, M.pr.branch), h('span', { class: 'count' }, String(M.pr.head).slice(0, 7)), h('span', {}, M.pr.date), h('span', { html: `${fs.length} files <b class="add" style="color:var(--add)">+${added}</b> <b style="color:var(--del)">−${removed}</b>` }), h('span', {}, `Updated ${M.updated || ''}`));
    if (M.session && M.session.url) meta.append(pill(M.session.url, M.session.name || `session ${String(M.session.id || '').slice(0, 8)}`));
    el.append(meta);
    el.append(h('div', { class: 'row' }, h('span', { class: 'lbl' }, 'Background:'), ...[['lavender', 'Lavender', '#cbc4e0'], ['sand', 'Sand', '#e3d9c6'], ['dark', 'Dark', '#171a24']].map(([k, n, c]) => h('button', { class: 'btn', 'data-set-theme': k, onclick: '' }, h('span', { class: 'swatch', style: `background:${c}` }), n))));
    el.append(h('div', { class: 'row' }, h('span', { class: 'lbl' }, 'JSON tiles:'), ...[['cell', 'Cell type'], ['classic', 'Classic']].map(([k, n]) => h('button', { class: 'btn', 'data-set-json': k }, n))));
    el.querySelectorAll('[data-set-theme]').forEach(b => b.onclick = () => setTheme(b.dataset.setTheme));
    el.querySelectorAll('[data-set-json]').forEach(b => b.onclick = () => setJson(b.dataset.setJson));
    el.append(legend());
    el.append(h('nav', { class: 'nav' }, (M.sections || []).map((s, i) => h('a', { class: 'pill', href: '#' + (s.id || slug(s.title || `section-${i}`)) }, s.title))));
    return el;
  }
  function legend() {
    const sw = (name, c, edge) => h('span', { class: 'sw' + (edge ? ' edge' : '') }, h('i', { style: `border-color:${c};${edge ? '' : 'background:' + c}` }), name);
    const hl = (name, cls) => h('span', { class: `hl ${cls}` }, name);
    const sample = { path: 'x', anchor: '', added: 14, removed: 19, lines: 135 };
    const rows = [
      ['Modules', (M.modules || []).map((m, i) => sw(m.name, color(m.color, i), true))],
      ['Files', [h('span', { class: 'chip new' }, 'NEW'), h('span', { class: 'chip mod' }, '✎ modified'), h('span', { class: 'muted' }, 'in code: '), h('span', { class: 'chip new' }, 'added line'), h('span', { class: 'chip mod' }, 'changed line')]],
      ['Highlights', [hl('TypeName', 'hl-type'), hl('CONSTANT', 'hl-const'), hl('V104 · CR-P3 · IP-30', 'hl-id'), hl('42', 'hl-num'), hl('key word', 'hl-key')]],
      ['Code', [h('span', { class: 'codekey', html: '<span class="kw">keyword</span> <span class="ty">Type</span> <span class="fn">call()</span> <span class="st">"string"</span> <span class="nm">42 →</span> <span class="cm"># comment</span>' })]],
      ['Links', [countPill(sample), h('span', { class: 'muted' }, 'lines in the file'), h('span', { class: 'pill', html: 'View file ↗' }), h('span', { class: 'pill', html: `View changes ${delta(sample)} ↗` }), h('span', { class: 'muted' }, 'added · removed in this PR')]],
    ];
    if (M.legend) for (const k in M.legend) rows.push([k, M.legend[k].map((e, i) => sw(e.name, color(e.color, i), e.edge))]);
    const el = h('div', { class: 'legend' });
    rows.forEach(([k, v]) => el.append(h('div', { class: 'k' }, k), h('div', { class: 'v' }, v)));
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
