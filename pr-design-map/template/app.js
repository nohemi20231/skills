/* PR design map renderer. The agent writes map.json; scripts/pr-files.sh writes files.json; build.sh embeds
   both in the page as JSON blocks (#files-json, #map-json), and this merges them, map over files. */
(function () {
  'use strict';
  const embedded = id => { const el = document.getElementById(id); return el ? JSON.parse(el.textContent) : {}; };
  const isObj = v => v && typeof v === 'object' && !Array.isArray(v);
  const merge = (a, b) => { const out = { ...a }; for (const k in b) out[k] = isObj(a[k]) && isObj(b[k]) ? merge(a[k], b[k]) : b[k]; return out; };
  const M = window.MAP || merge(embedded('files-json'), embedded('map-json'));
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
  const secId = (s, i) => s.id || slug(s.title || `section-${i}`);
  const PHONE = window.matchMedia ? window.matchMedia('(max-width:800px)') : { matches: false };

  /* ---------- theme ---------- */
  function initTheme() {
    const q = new URLSearchParams(location.search);
    let t = q.get('theme'); if (t === 'light') t = 'slate';
    let j = q.get('json');
    try { t = t || localStorage.getItem('dm-theme') || 'slate'; j = j || localStorage.getItem('dm-json') || 'cell'; } catch (e) { t = t || 'slate'; j = j || 'cell'; }
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
  /* One line of a code or JSON block. Long lines wrap inside the tile (never a sideways scroll): the leading
     indent becomes --i (in characters) and a wrapped part hangs two characters further in, so a line's
     added / changed / unknown color covers all of its text. */
  const line = (indent, html, cls) => `<span class="ln${cls ? ' ' + cls : ''}" style="--i:${indent}">${html || ' '}</span>`;
  const indentOf = l => { const m = l.match(/^[ \t]*/)[0]; return { n: m.replace(/\t/g, '    ').length, rest: l.slice(m.length) }; };
  function codeBlock(code, edge) {
    if (!code) return null;
    const lang = code.lang || '';
    const added = new Set(code.added || []), changed = new Set(code.changed || []);
    const lines = String(code.text || '').replace(/\n$/, '').split('\n');
    const html = lines.map((l, i) => { const k = i + 1; const { n, rest } = indentOf(l); return line(n, tokenizeLine(rest, lang), added.has(k) ? 'added' : changed.has(k) ? 'changed' : ''); }).join('');
    const pre = h('pre', { class: 'code', html: `<code>${html}</code>` });
    if (edge) pre.style.setProperty('--edge', color(edge));
    return pre;
  }
  function jsonBlock(value, unknown) {
    const unk = new Set(unknown || []);
    const out = [];
    const push = (ind, html, bad) => out.push(line(ind * 2, bad ? `<span class="unknown">${html}</span>` : html));
    const scalar = v => Array.isArray(v) ? '[]' : v && typeof v === 'object' ? '{}' : typeof v === 'string' ? `<span class="st">${esc(JSON.stringify(v))}</span>` : typeof v === 'number' ? `<span class="nm">${v}</span>` : `<span class="kw">${String(v)}</span>`;
    /* writes v starting on a line that begins with prefix; an unknown key marks every line of its value */
    const emit = (v, path, ind, prefix, comma, bad) => {
      const arr = Array.isArray(v) && v.length, obj = !Array.isArray(v) && v && typeof v === 'object' && Object.keys(v).length;
      if (!arr && !obj) return push(ind, prefix + scalar(v) + comma, bad);
      push(ind, prefix + (arr ? '[' : '{'), bad);
      if (arr) v.forEach((x, i) => emit(x, `${path}[${i}]`, ind + 1, '', i < v.length - 1 ? ',' : '', bad));
      else Object.keys(v).forEach((k, i, keys) => { const p = path ? `${path}.${k}` : k; emit(v[k], p, ind + 1, `<span class="ty">${esc(JSON.stringify(k))}</span>: `, i < keys.length - 1 ? ',' : '', bad || unk.has(p)); });
      push(ind, (arr ? ']' : '}') + comma, bad);
    };
    emit(value, '', 0, '', '', false);
    return h('pre', { class: 'json', html: `<code>${out.join('')}</code>` });
  }

  /* ---------- prose highlights ---------- */
  const HL = /\*\*(.+?)\*\*|\b([A-Z][a-z0-9]+(?:[A-Z][a-z0-9]*)+)\b|\b([A-Z][A-Z0-9_]{2,})\b|\b([A-Z]{1,3}-[A-Z]?\d{1,4}[a-z]?|[VDOR]\d{1,4})\b|\b(\d+(?:\.\d+)?)\b/g;
  const SKIP = 'pre,code,a,h1,h2,h3,.pill,.chip,.count,.btn,.legend,.tag,svg,.tile>h3,.path,.grid,.topbar,.sidebar,.sheet,.summary,button,select';
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
  const sv = (tag, attrs, text) => { const e = document.createElementNS(NS, tag); for (const k in attrs || {}) if (attrs[k] != null) e.setAttribute(k, attrs[k]); if (text != null) e.textContent = text; return e; };
  function svgRoot() { const s = sv('svg'); const d = sv('defs'); d.innerHTML = Object.entries(COLORS).map(([k, v]) => `<marker id="arr-${k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="${v}"/></marker>`).join(''); s.append(d); return s; }
  /* viewBox fitted to what was drawn (y0..y1), so a figure carries no empty bands; aspect-ratio keeps the height in step when max-width shrinks it.
     The figure may shrink a wide diagram to 87.5% at most (16px text stays at 14px); past that it scrolls. */
  function fit(svg, w, y0, y1) { const hgt = Math.round(y1 - y0); svg.setAttribute('viewBox', `0 ${Math.round(y0)} ${w} ${hgt}`); svg.setAttribute('width', w); svg.setAttribute('height', hgt); svg.style.aspectRatio = `${w} / ${hgt}`; svg.style.minWidth = `${Math.round(w * 0.875)}px`; }
  const markerFor = c => `url(#arr-${Object.keys(COLORS).find(k => COLORS[k] === c) || 'gray'})`;
  /* an arrow label over a halo: a copy stroked in the tile colour drawn first, the text on top. (One stroked text with paint-order lets
     each glyph's stroke cover its neighbour's fill in some renderers, which breaks the letters.) */
  function label(svg, x, y, text, cls, anchor) {
    const a = { x, y, 'text-anchor': anchor || 'middle' };
    svg.append(sv('text', { ...a, class: `halo ${cls || 'arrow'}`, 'aria-hidden': 'true' }, text), sv('text', { ...a, class: cls || 'arrow' }, text));
  }
  function box(svg, x, y, w, hgt, title, sub, col) {
    svg.append(sv('rect', { x, y, width: w, height: hgt, rx: 12, class: 'box', stroke: col }));
    svg.append(sv('text', { x: x + w / 2, y: y + (sub ? hgt / 2 - 6 : hgt / 2 + 8), 'text-anchor': 'middle', class: 'title' }, title));
    if (sub) svg.append(sv('text', { x: x + w / 2, y: y + hgt / 2 + 20, 'text-anchor': 'middle', class: 'sub' }, sub));
  }

  /* boxes in a row with labelled arrows; used by modules and lifecycle diagrams */
  function boxesDiagram(nodes, edges) {
    const W = 210, H = 84, GAP = 100, perRow = Math.min(nodes.length, 4);   // four boxes fit the 1196px figure unscaled
    const rows = Math.ceil(nodes.length / perRow), ROWH = 230;
    const width = perRow * W + (perRow - 1) * GAP + 40;
    const svg = svgRoot();
    const pos = {};
    let top = 90, bottom = 90 + (rows - 1) * ROWH + H;   // drawn extent; arcs and labels push it out
    nodes.forEach((n, i) => { const r = Math.floor(i / perRow), c = i % perRow; const x = 20 + c * (W + GAP), y = 90 + r * ROWH; pos[n.name] = { x, y, i, row: r, col: color(n.color, i) }; box(svg, x, y, W, H, n.name, n.sub, pos[n.name].col); });
    const used = {};
    (edges || []).forEach(e => {
      const a = pos[e.from], b = pos[e.to]; if (!a || !b) return;
      const col = a.col, key = a.i < b.i ? `${a.i}-${b.i}` : `${b.i}-${a.i}`; used[key] = (used[key] || 0) + 1;
      const forward = a.i < b.i, sameRow = a.row === b.row, adjacent = sameRow && Math.abs(a.i - b.i) === 1;
      let d, lx, ly, anchor;
      if (adjacent) {
        // straight line between neighbours: forward above the middle, back below; label on the far side of the line
        const y = a.y + H / 2 + (forward ? -12 : 12); const x1 = forward ? a.x + W : a.x, x2 = forward ? b.x : b.x + W;
        d = `M${x1},${y} L${x2},${y}`; lx = (x1 + x2) / 2; ly = y + (forward ? -10 : 24);
      } else if (a === b) {
        // self-loop on the top-left corner, label above it
        d = `M${a.x + 20},${a.y} C${a.x + 20},${a.y - 60} ${a.x + 80},${a.y - 60} ${a.x + 80},${a.y}`; lx = a.x; ly = a.y - 68; anchor = 'start'; top = Math.min(top, ly - 20);
      } else if (!sameRow) {
        // between rows: an S-curve from the bottom of the upper box to the top of the lower one;
        // the label sits above the flat middle of the S, or right of the line when it is nearly vertical
        const down = a.row < b.row; const ya = down ? a.y + H : a.y, yb = down ? b.y : b.y + H; const x1 = a.x + W / 2, x2 = b.x + W / 2, ym = (ya + yb) / 2;
        d = `M${x1},${ya} C${x1},${ym} ${x2},${ym} ${x2},${yb}`;
        if (Math.abs(x1 - x2) < 80) { lx = Math.max(x1, x2) + 12; ly = ym + 6; anchor = 'start'; } else { lx = (x1 + x2) / 2; ly = ym - 10; }
      } else {
        // skip arc over the boxes in between, leaving right of centre (so a self-loop never crosses it); label clear of the apex
        const up = forward; const y0 = up ? a.y : a.y + H; const lift = (up ? -1 : 1) * (40 + 22 * used[key]); const apex = y0 + lift * 0.75;
        const x1 = a.x + W / 2 + (forward ? 30 : -30), x2 = b.x + W / 2 + (forward ? -30 : 30);
        d = `M${x1},${y0} C${x1},${y0 + lift} ${x2},${y0 + lift} ${x2},${up ? b.y : b.y + H}`; lx = (x1 + x2) / 2;
        if (up) { ly = apex - 10; top = Math.min(top, ly - 20); } else { ly = apex + 24; bottom = Math.max(bottom, ly + 8); }
      }
      svg.append(sv('path', { d, fill: 'none', stroke: col, 'stroke-width': 3, 'marker-end': markerFor(col) }));
      if (e.label) label(svg, lx, ly, e.label, null, anchor);
    });
    fit(svg, width, top - 24, bottom + 24);
    return svg;
  }

  function sequenceDiagram(s) {
    const actors = s.actors || [], steps = s.steps || [];
    const LW = 210, GAP = 60, TOP = 110, STEP = 96;
    const width = actors.length * (LW + GAP) + 20, height = TOP + Math.max(steps.length - 1, 0) * STEP + 60;   // last value label plus a margin
    const svg = svgRoot();
    const cx = {};
    actors.forEach((a, i) => { const x = 20 + i * (LW + GAP); const col = color(a.color, i); cx[a.name] = x + LW / 2; box(svg, x, 16, LW, 70, a.name, a.sub, col); svg.append(sv('line', { x1: x + LW / 2, y1: 86, x2: x + LW / 2, y2: height - 16, class: 'lane' })); cx['#' + a.name] = col; });
    steps.forEach((st, i) => {
      const x1 = cx[st.from], x2 = cx[st.to]; if (x1 == null || x2 == null) return;
      const y = TOP + i * STEP; const col = cx['#' + st.from]; const dir = x2 > x1 ? 1 : -1;
      svg.append(sv('line', { x1: x1 + dir * 4, y1: y, x2: x2 - dir * 12, y2: y, stroke: col, 'stroke-width': 3, 'marker-end': markerFor(col), 'stroke-dasharray': st.reply ? '8 6' : null }));
      const mx = (x1 + x2) / 2; label(svg, mx, y - 12, st.label || '');
      if (st.value) label(svg, mx, y + 28, st.value, 'sub');
    });
    fit(svg, width, 0, height);
    return svg;
  }

  function treeDiagram(roots) {
    let longest = 0; const measure = n => { longest = Math.max(longest, (n.name || '').length); (n.children || []).forEach(measure); }; roots.forEach(measure);
    const W = Math.max(230, longest * 12.5 + 30), H = 56, DX = W + 60, DY = 74; let leaf = 0;
    const layout = (n, depth) => { n._d = depth; if (n.children && n.children.length) { n.children.forEach(c => layout(c, depth + 1)); n._y = (n.children[0]._y + n.children[n.children.length - 1]._y) / 2; } else n._y = leaf++ * DY; };
    roots.forEach(r => { layout(r, 0); leaf += 0.4; });
    let depth = 0; const walk = (n, f) => { f(n); (n.children || []).forEach(c => walk(c, f)); };
    roots.forEach(r => walk(r, n => { depth = Math.max(depth, n._d); }));
    const svg = svgRoot(); let bottom = 0;
    roots.forEach(r => walk(r, n => {
      const x = 20 + n._d * DX, y = 20 + n._y; const col = color(n.color, n._d);
      box(svg, x, y, W, H, n.name, n.sub, col); bottom = Math.max(bottom, y + H);
      (n.children || []).forEach(c => { const cy = 20 + c._y + H / 2; svg.append(sv('path', { d: `M${x + W},${y + H / 2} L${x + W + 30},${y + H / 2} L${x + W + 30},${cy} L${x + DX},${cy}`, fill: 'none', stroke: col, 'stroke-width': 3, 'marker-end': markerFor(col) })); });
    }));
    fit(svg, (depth + 1) * DX + 20, 0, bottom + 20);
    return svg;
  }

  /* ---------- components ---------- */
  function section(s, i) {
    const wrap = h('section', { id: secId(s, i), 'data-files': (s.files || []).join(',') });
    wrap.append(h('h2', {}, s.title || ''));
    const R = RENDER[s.type]; if (R) wrap.append(...[R(s)].flat(3).filter(Boolean)); else wrap.append(h('p', { class: 'muted' }, `unknown section type ${s.type}`));
    return wrap;
  }
  /* a tile whose full-width header bar ("<label> … Hide ▴ / Show ▾") folds what is under it, open at first; folded, the bar stays */
  function foldTile(label, kind, ...body) {
    const act = h('span', { class: 'act' }, 'Hide ▴');
    const btn = h('button', { type: 'button', class: 'fold-btn', 'aria-expanded': 'true' }, h('span', {}, label), act);
    const fold = h('div', { class: `fold bar ${kind} open` }, btn, ...body);
    btn.onclick = () => { const open = fold.classList.toggle('open'); btn.setAttribute('aria-expanded', String(open)); act.textContent = open ? 'Hide ▴' : 'Show ▾'; };
    return fold;
  }
  /* a diagram sits in a "Diagram" fold tile. The figure scrolls sideways at a readable size; a "Swipe sideways" line shows while it overflows */
  const fig = svg => {
    const f = h('figure', {}, svg), hint = h('p', { class: 'swipe' }, 'Swipe sideways to see all of it ⇆');
    const fits = () => f.classList.toggle('overflows', f.scrollWidth > f.clientWidth + 1);
    if (window.ResizeObserver) new ResizeObserver(fits).observe(f); else requestAnimationFrame(fits);
    return foldTile('Diagram', 'diagram', f, hint);
  };
  /* "What changed": the map's short summary (a few bullets) in a fold tile under the PR facts; nothing when the map has none */
  function brief() {
    const items = [].concat(M.summary || []).filter(Boolean);
    return items.length ? foldTile('What changed', 'brief', h('ul', {}, items.map(t => h('li', {}, t)))) : null;
  }
  function table(t) {
    const cols = t.columns || [];
    const tb = h('table');
    if (cols.length) tb.append(h('thead', {}, h('tr', {}, cols.map(c => h('th', {}, c)))));
    tb.append(h('tbody', {}, (t.rows || []).map(r => h('tr', {}, r.map((c, j) => { const td = h('td', { 'data-label': cols[j] }, String(c)); if (c === '✓' || c === 'yes') td.className = 'yes'; if (c === '✗' || c === 'no') td.className = 'no'; if (j === 0) td.style.fontWeight = '700'; return td; })))));
    // a wide table scrolls inside its wrapper; with more than three columns it becomes one card per row on a phone
    return h('div', { class: 'scroll' + (cols.length > 3 ? ' cards' : '') }, tb);
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
    const el = h('div', { class: 'tile' + (n.code ? ' wide' : '') }); el.style.setProperty('--tile-color', color(mod && mod.color, i));
    const head = h('h3', {}, n.class || f.path.split('/').pop());
    if (isNew(f)) head.append(h('span', { class: 'chip new' }, 'NEW')); else if (isMod(f)) head.append(h('span', { class: 'chip mod' }, '✎ modified'));
    if (n.layer) head.append(h('span', { class: 'chip layer' }, n.layer));
    if (n.kind) head.append(h('span', { class: 'chip' }, n.kind));
    const right = h('span', { class: 'right' }, countPill(f), pill(fileUrl(f), 'View file'));
    if (isNew(f) || isMod(f)) right.append(changesPill(f));
    head.append(right); el.append(head);
    el.append(h('p', { class: 'muted path' }, f.path));
    if (n.lines) el.append(h('ul', {}, n.lines.map(l => h('li', {}, l))));
    if (n.change && !n.lines) el.append(h('p', {}, n.change));
    if (n.code) {
      // folds behind a "Code · n lines" button: closed on a phone, open on wider screens
      const count = String(n.code.text || '').replace(/\n$/, '').split('\n').length, open = !PHONE.matches;
      const btn = h('button', { type: 'button', class: 'fold-btn', 'aria-expanded': String(open) }, `Code · ${count} lines`);
      const fold = h('div', { class: 'fold' + (open ? ' open' : '') }, btn, codeBlock(n.code, mod && mod.color));
      btn.onclick = () => btn.setAttribute('aria-expanded', String(fold.classList.toggle('open')));
      el.append(fold);
    }
    return el;
  }
  function filesGrid() {
    const mods = M.modules || [], layers = M.layers || [];
    const g = h('div', { class: 'grid' }); g.style.gridTemplateColumns = `150px repeat(${mods.length}, minmax(0,1fr))`;
    // a column needs 190px to be read; narrower than that (a phone, a side panel, many modules) the grid becomes a list
    const need = 150 + 190 * mods.length;
    const fitList = () => g.classList.toggle('list', g.clientWidth < need);
    if (window.ResizeObserver) new ResizeObserver(fitList).observe(g); else { window.addEventListener('resize', fitList); requestAnimationFrame(fitList); }
    g.append(h('div'));
    mods.forEach((m, i) => { const d = h('div', { class: 'head' }, m.name); d.style.setProperty('--col', color(m.color, i)); g.append(d); });
    layers.forEach(layer => {
      g.append(h('div', { class: 'side' }, layer));
      mods.forEach((m, i) => {
        const fs = files().filter(f => note(f).module === m.name && note(f).layer === layer);
        const cell = h('div', { class: 'cell' + (fs.length ? '' : ' empty'), 'data-module': m.name }); cell.style.setProperty('--col', color(m.color, i));
        if (!fs.length) cell.append(h('span', { class: 'sr' }, 'no change'));
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
    lifecycle: s => { const states = (s.states || []).map((st, i) => typeof st === 'string' ? { name: st, color: CYCLE[i % CYCLE.length] } : st); return fig(boxesDiagram(states, s.transitions)); },
    proposal: s => [
      h('h3', {}, 'CURRENT'), h('div', { class: 'tiles stack' }, tile({ ...s.current, color: s.current.color || 'gray' }, 0)),
      ...(s.options || []).map((o, i) => [h('h3', {}, `MODIFIED · ${o.title}`), h('div', { class: 'tiles stack' }, tile({ ...o, title: o.title }, i + 1))]).flat(),
      s.comparison ? table(s.comparison) : null,
      s.decisions ? h('div', { class: 'tiles' }, s.decisions.map(tile)) : null,
    ],
  };

  /* ---------- header, top bar, sidebar, panels ---------- */
  function header() {
    const fs = M.files || []; const added = fs.reduce((a, f) => a + (f.added || 0), 0), removed = fs.reduce((a, f) => a + (f.removed || 0), 0);
    const el = h('header', { class: 'top' });
    el.append(h('h1', {}, `${M.app} Design Map: PR #${M.pr.number}`));
    // phones show the first three facts on one line; the rest (.sec) open with "More"
    const stat = (k, v, sec) => h('div', { class: 'stat' + (sec ? ' sec' : '') }, h('span', { class: 'k' }, k), h('span', { class: 'v' }, v));
    const summary = h('div', { class: 'summary' },
      stat('Pull request', pill(prUrl(), `PR #${M.pr.number}`)),
      stat('Head', h('span', { class: 'count' }, String(M.pr.head).slice(0, 7))),
      stat('Changes', h('span', { html: `${fs.length} files <b class="add">+${added}</b> <b class="del">−${removed}</b>` })),
      stat('Branch', M.pr.branch || '', true),
      stat('Date', M.pr.date || '', true),
      stat('Updated', M.updated || '', true));
    if (M.session && M.session.url) summary.append(stat('Session', pill(M.session.url, M.session.name || `session ${String(M.session.id || '').slice(0, 8)}`), true));
    const more = h('button', { class: 'more-btn', type: 'button', 'aria-expanded': 'false' }, 'More ▾');
    more.onclick = () => { const on = el.classList.toggle('show-more'); more.setAttribute('aria-expanded', on); more.textContent = on ? 'Less ▴' : 'More ▾'; };
    summary.append(more);
    el.append(summary, brief());
    return el;
  }
  const toolBtn = (text, sheetId, label) => { const b = h('button', { class: 'btn', type: 'button', 'aria-haspopup': 'dialog', 'aria-controls': sheetId, 'aria-label': label }, text); b.onclick = () => openSheet(sheetId, b); return b; };
  /* under 1400px: a sticky bar with a section picker, Key and Settings */
  function topbar(secs) {
    const sel = h('select', { class: 'jump', 'aria-label': 'Jump to section' }, h('option', { value: '' }, 'Sections'), secs.map(([id, t]) => h('option', { value: id }, t)));
    sel.onchange = () => { const t = sel.value && document.getElementById(sel.value); if (t) t.scrollIntoView(); };
    return h('div', { class: 'topbar' }, h('div', { class: 'bar-in' }, h('span', { class: 'jump-wrap' }, sel), h('span', { class: 'tools' }, toolBtn('Key', 'sheet-key'), toolBtn(h('span', { class: 'ico', 'aria-hidden': 'true' }, '⚙'), 'sheet-settings', 'Settings'))));
  }
  /* 1400px and wider: a sticky sidebar with the section list, Key and Settings */
  function sidebar(secs) {
    return h('aside', { class: 'sidebar' },
      h('div', { class: 'side-app' }, M.app || ''), h('div', { class: 'side-pr' }, `PR #${M.pr.number}`),
      h('nav', { class: 'toc', 'aria-label': 'Sections' }, secs.map(([id, t]) => h('a', { href: '#' + id, 'data-toc': id }, t))),
      h('div', { class: 'side-tools' }, toolBtn('Key', 'sheet-key'), toolBtn([h('span', { class: 'ico', 'aria-hidden': 'true' }, '⚙'), 'Settings'], 'sheet-settings')));
  }
  function settings() {
    const seg = (label, attr, opts) => h('div', { class: 'set' }, h('div', { class: 'lbl' }, label), h('div', { class: 'seg', role: 'group', 'aria-label': label }, opts.map(([k, n, c]) => h('button', { type: 'button', [attr]: k, 'aria-pressed': 'false' }, c ? h('span', { class: 'swatch', style: `background:${c}` }) : null, n))));
    const el = h('div', {},
      seg('Background', 'data-set-theme', [['slate', 'Slate', '#d5dae3'], ['lavender', 'Lavender', '#cbc4e0'], ['sand', 'Sand', '#e3d9c6'], ['dark', 'Dark', '#171a24']]),
      seg('JSON tiles', 'data-set-json', [['cell', 'Cell type'], ['classic', 'Classic']]));
    el.querySelectorAll('[data-set-theme]').forEach(b => b.onclick = () => setTheme(b.dataset.setTheme));
    el.querySelectorAll('[data-set-json]').forEach(b => b.onclick = () => setJson(b.dataset.setJson));
    return el;
  }
  /* Key and Settings open as a panel (a bottom sheet on a phone); Esc, the backdrop or × closes it */
  let opener = null;
  function sheet(id, title, body) {
    const close = h('button', { class: 'btn', type: 'button', 'aria-label': 'Close' }, '×'); close.onclick = closeSheets;
    return h('div', { class: 'sheet', id, role: 'dialog', 'aria-modal': 'true', 'aria-label': title, hidden: '' }, h('div', { class: 'sheet-head' }, h('h2', {}, title), close), h('div', { class: 'sheet-body' }, body));
  }
  function openSheet(id, from) {
    closeSheets(); opener = from || null;
    const s = document.getElementById(id); if (!s) return;
    document.querySelector('.backdrop').hidden = false; s.hidden = false; document.documentElement.classList.add('sheet-open');
    s.querySelector('.sheet-head .btn').focus();
  }
  function closeSheets() {
    const open = document.querySelector('.sheet:not([hidden])'); if (!open) return;
    open.hidden = true; document.querySelector('.backdrop').hidden = true; document.documentElement.classList.remove('sheet-open');
    if (opener) { opener.focus(); opener = null; }
  }
  /* the section being read is marked in the sidebar and shown in the top bar's picker */
  function spy(secs) {
    if (!window.IntersectionObserver) return;
    const sel = document.querySelector('.jump'), links = {};
    document.querySelectorAll('[data-toc]').forEach(a => { links[a.dataset.toc] = a; });
    const seen = {};
    const io = new IntersectionObserver(es => {
      es.forEach(e => { seen[e.target.id] = e.isIntersecting; });
      const cur = secs.map(([id]) => id).find(id => seen[id]); if (!cur) return;
      for (const id in links) { if (id === cur) links[id].setAttribute('aria-current', 'true'); else links[id].removeAttribute('aria-current'); }
      if (sel) sel.value = cur;
    }, { rootMargin: '-80px 0px -55% 0px' });
    secs.forEach(([id]) => { const e = document.getElementById(id); if (e) io.observe(e); });
  }
  function legend() {
    const sw = (name, c, edge) => h('span', { class: 'sw' + (edge ? ' edge' : '') }, h('i', { style: `border-color:${c};${edge ? '' : 'background:' + c}` }), name);
    const hl = (name, cls) => h('span', { class: `hl ${cls}` }, name);
    const sample = { path: 'x', anchor: '', added: 14, removed: 19, lines: 135 };
    const rows = [
      ['Modules', (M.modules || []).map((m, i) => sw(m.name, color(m.color, i), true))],
      ['Files', [h('span', { class: 'chip new' }, 'NEW'), h('span', { class: 'chip mod' }, '✎ modified'), h('span', { class: 'muted' }, 'in code: '), h('span', { class: 'codekey', html: '<span class="ln added">added line</span><span class="ln changed">changed line</span>' })]],
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
    const secs = (M.sections || []).map((s, i) => [secId(s, i), s.title || '']);
    root.append(header(), ...(M.sections || []).map(section));
    const layout = root.parentElement; layout.insertBefore(sidebar(secs), root); layout.parentElement.insertBefore(topbar(secs), layout);
    const backdrop = h('div', { class: 'backdrop', hidden: '' }); backdrop.onclick = closeSheets;
    document.body.append(backdrop, sheet('sheet-key', 'Key', legend()), sheet('sheet-settings', 'Settings', settings()));
    document.addEventListener('keydown', e => { if (e.key === 'Escape') closeSheets(); });
    highlightProse(root); initTheme(); spy(secs);
  }
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', main) : main();
})();
