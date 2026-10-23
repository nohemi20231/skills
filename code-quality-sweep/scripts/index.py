#!/usr/bin/env python3
"""Local hybrid search index for the code-quality-sweep skill.

One SQLite file holds code chunks (one per function or class), decision
log entries, open questions, skill sections and co-change pairs, each
with a full-text row and an embedding. Search fuses full-text rank and
vector similarity, so exact names and fuzzy questions both work.

Usage:
  index.py build  [--repo DIR]                 index the whole repo
  index.py update [--repo DIR] [FILE ...]      re-index changed files (default: since last build)
  index.py search QUERY [--kind K] [--limit N] [--path PREFIX] [--json]
  index.py status

Environment:
  SWEEP_DIR       state folder, default <repo>/.claude/sweep
  SWEEP_EMBEDDER  "hash" (default, no model needed) or "ollama[:model]"
                  for a local Ollama server (default model nomic-embed-text)
  OLLAMA_URL      default http://localhost:11434

Standard library only. If numpy is installed it is used for the vector
scan, otherwise a pure-Python scan runs; both give the same results.
"""
from __future__ import annotations

import argparse
import array
import fnmatch
import hashlib
import json
import math
import os
import re
import sqlite3
import subprocess
import sys
import urllib.request

CODE_EXT = {
    ".py", ".java", ".kt", ".kts", ".cs", ".js", ".jsx", ".ts", ".tsx", ".mjs",
    ".go", ".rs", ".rb", ".scala", ".swift", ".php", ".c", ".h", ".cc", ".cpp", ".hpp",
}
MAX_FILE_BYTES = 200_000
MAX_CHUNK_LINES = 150
WINDOW_LINES = 60
HASH_DIM = 256

# Definition starts, per language family. Group "name" is the symbol.
DEF_PATTERNS = {
    "python": [
        r"^\s*(?:async\s+)?def\s+(?P<name>\w+)",
        r"^\s*class\s+(?P<name>\w+)",
    ],
    "jvm": [  # java, kotlin, scala, c#
        r"^\s*(?:(?:public|private|protected|abstract|final|static|sealed|data|open|inner|internal|partial)\s+)*(?:class|interface|enum|record|object|struct)\s+(?P<name>\w+)",
        r"^\s*(?:(?:override|open|private|public|protected|internal|suspend|inline)\s+)*fun\s+(?:<[^>]*>\s*)?(?:[\w.]+\.)?(?P<name>\w+)\s*\(",
        r"^\s*(?:(?:public|private|protected|static|final|synchronized|abstract|default|override|async|virtual|internal)\s+)+[\w<>\[\],.?\s]+?\s+(?P<name>\w+)\s*\([^;]*$",
        r"^\s*def\s+(?P<name>\w+)",
    ],
    "js": [
        r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*(?P<name>\w+)",
        r"^\s*(?:export\s+)?(?:default\s+)?(?:abstract\s+)?class\s+(?P<name>\w+)",
        r"^\s*(?:export\s+)?(?:const|let|var)\s+(?P<name>\w+)\s*(?::[^=]+)?=\s*(?:async\s*)?(?:\([^)]*\)|\w+)\s*(?::[^=]+)?=>",
        r"^\s{2,}(?:(?:public|private|protected|static|async|readonly|override)\s+)*(?P<name>\w+)\s*\([^;]*\)\s*(?::\s*[\w<>\[\]|,.\s]+)?\s*\{\s*$",
    ],
    "go": [
        r"^func\s+(?:\([^)]*\)\s*)?(?P<name>\w+)",
        r"^type\s+(?P<name>\w+)",
    ],
    "rust": [
        r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:unsafe\s+)?(?:fn|struct|enum|trait|mod)\s+(?P<name>\w+)",
        r"^\s*impl(?:<[^>]*>)?\s+(?:[\w:]+\s+for\s+)?(?P<name>[\w:]+)",
    ],
    "ruby": [r"^\s*(?:def|class|module)\s+(?P<name>[\w.?!]+)"],
    "c": [
        r"^[\w\s\*<>:,]+?\b(?P<name>\w+)\s*\([^;]*\)\s*(?:const\s*)?\{?\s*$",
        r"^\s*(?:typedef\s+)?(?:struct|class|enum|union)\s+(?P<name>\w+)",
    ],
}
EXT_FAMILY = {
    ".py": "python", ".java": "jvm", ".kt": "jvm", ".kts": "jvm", ".cs": "jvm", ".scala": "jvm",
    ".js": "js", ".jsx": "js", ".ts": "js", ".tsx": "js", ".mjs": "js",
    ".go": "go", ".rs": "rust", ".rb": "ruby", ".swift": "jvm", ".php": "jvm",
    ".c": "c", ".h": "c", ".cc": "c", ".cpp": "c", ".hpp": "c",
}
COMPILED = {fam: [re.compile(p) for p in pats] for fam, pats in DEF_PATTERNS.items()}


# --- paths and git -----------------------------------------------------------

def git(repo: str, *args: str) -> str:
    out = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {out.stderr.strip()}")
    return out.stdout


def repo_root(start: str) -> str:
    return git(start, "rev-parse", "--show-toplevel").strip()


def sweep_dir(repo: str) -> str:
    d = os.environ.get("SWEEP_DIR") or os.path.join(repo, ".claude", "sweep")
    os.makedirs(d, exist_ok=True)
    return d


def db_path(repo: str) -> str:
    return os.path.join(sweep_dir(repo), "index.db")


def ignore_globs(repo: str) -> list[str]:
    p = os.path.join(sweep_dir(repo), "ignore")
    if not os.path.exists(p):
        return []
    with open(p, encoding="utf-8", errors="replace") as f:
        return [l.strip() for l in f if l.strip() and not l.startswith("#")]


def ignored(path: str, globs: list[str]) -> bool:
    base = os.path.basename(path)
    for g in globs:
        if fnmatch.fnmatch(path, g) or fnmatch.fnmatch(base, g):
            return True
        if g.startswith("**/") and fnmatch.fnmatch(path, g[3:]):
            return True
    return False


def tracked_code_files(repo: str) -> list[str]:
    globs = ignore_globs(repo)
    files = []
    for line in git(repo, "ls-files").splitlines():
        if os.path.splitext(line)[1] in CODE_EXT and not ignored(line, globs):
            files.append(line)
    return files


# --- embeddings --------------------------------------------------------------

_TOKEN = re.compile(r"[A-Za-z][a-z]+|[A-Z]+(?![a-z])|\d+")


def tokens(text: str) -> list[str]:
    """Split identifiers on camelCase and snake_case, lowercase everything."""
    return [t.lower() for t in _TOKEN.findall(text)]


class HashEmbedder:
    """Hashing-trick bag of tokens. No model, no network, deterministic."""
    name = "hash"
    dim = HASH_DIM

    def embed(self, text: str) -> list[float]:
        v = [0.0] * self.dim
        for t in tokens(text):
            h = int(hashlib.blake2b(t.encode(), digest_size=8).hexdigest(), 16)
            v[h % self.dim] += 1.0 if (h >> 63) else -1.0
        n = math.sqrt(sum(x * x for x in v)) or 1.0
        return [x / n for x in v]


class OllamaEmbedder:
    def __init__(self, model: str):
        self.model = model
        self.name = f"ollama:{model}"
        self.url = os.environ.get("OLLAMA_URL", "http://localhost:11434").rstrip("/")
        self.dim = len(self.embed("probe"))

    def embed(self, text: str) -> list[float]:
        body = json.dumps({"model": self.model, "prompt": text[:8000]}).encode()
        req = urllib.request.Request(self.url + "/api/embeddings", data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.load(r)["embedding"]
        except Exception as e:  # noqa: BLE001
            raise SystemExit(f"ollama embedding failed ({self.url}, {self.model}): {e}")


def embedder():
    spec = os.environ.get("SWEEP_EMBEDDER", "hash")
    if spec == "hash":
        return HashEmbedder()
    if spec.startswith("ollama"):
        return OllamaEmbedder(spec.split(":", 1)[1] if ":" in spec else "nomic-embed-text")
    raise SystemExit(f"unknown SWEEP_EMBEDDER: {spec}")


def pack(v: list[float]) -> bytes:
    return array.array("f", v).tobytes()


def unpack(b: bytes) -> list[float]:
    a = array.array("f")
    a.frombytes(b)
    return list(a)


# --- chunking ----------------------------------------------------------------

def read_text(path: str) -> str | None:
    try:
        if os.path.getsize(path) > MAX_FILE_BYTES:
            return None
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def chunk_code(rel: str, text: str) -> list[dict]:
    """One chunk per definition, from its start to the next start, capped."""
    lines = text.splitlines()
    fam = EXT_FAMILY.get(os.path.splitext(rel)[1])
    starts: list[tuple[int, str]] = []
    for i, line in enumerate(lines):
        for pat in COMPILED.get(fam, []):
            m = pat.match(line)
            if m:
                starts.append((i, m.group("name")))
                break
    chunks = []
    if not starts:
        for i in range(0, len(lines), WINDOW_LINES):
            body = "\n".join(lines[i:i + WINDOW_LINES])
            if body.strip():
                chunks.append({"kind": "code", "path": rel, "start": i + 1,
                               "end": min(i + WINDOW_LINES, len(lines)), "symbol": "", "text": body})
        return chunks
    if starts[0][0] > 0:
        head = "\n".join(lines[:min(starts[0][0], 40)])
        if head.strip():
            chunks.append({"kind": "code", "path": rel, "start": 1, "end": min(starts[0][0], 40),
                           "symbol": "(header)", "text": head})
    for n, (i, name) in enumerate(starts):
        end = starts[n + 1][0] if n + 1 < len(starts) else len(lines)
        end = min(end, i + MAX_CHUNK_LINES)
        chunks.append({"kind": "code", "path": rel, "start": i + 1, "end": end,
                       "symbol": name, "text": "\n".join(lines[i:end])})
    return chunks


_HEADING = re.compile(r"^##\s+(.*)$")
_DECISION_ID = re.compile(r"\b(grouped|reverted|answered|decided)\s+(\S+)")


def chunk_markdown(rel: str, text: str, kind: str, prefix: str = "") -> list[dict]:
    """One chunk per '## ' section. The heading is the symbol."""
    lines = text.splitlines()
    chunks, cur, cur_start, title = [], [], 1, ""

    def flush(end):
        body = "\n".join(cur).strip()
        if body:
            chunks.append({"kind": kind, "path": rel, "start": cur_start, "end": end,
                           "symbol": (prefix + title).strip(), "text": body})

    for i, line in enumerate(lines):
        m = _HEADING.match(line)
        if m:
            flush(i)
            cur, cur_start, title = [line], i + 1, m.group(1).strip()
        else:
            cur.append(line)
    flush(len(lines))
    return chunks


def chunk_cochange(path: str) -> list[dict]:
    chunks = []
    try:
        with open(path, encoding="utf-8") as f:
            rows = f.read().splitlines()
    except OSError:
        return chunks
    for n, row in enumerate(rows[1:], start=2):
        parts = row.split()
        if len(parts) == 3 and parts[2].isdigit():
            a, b, c = parts
            chunks.append({"kind": "cochange", "path": "cochange.tsv", "start": n, "end": n,
                           "symbol": f"{a} + {b}",
                           "text": f"{a} and {b} change together, {c} times"})
        elif len(parts) == 2 and parts[0] == "hub":
            chunks.append({"kind": "cochange", "path": "cochange.tsv", "start": n, "end": n,
                           "symbol": parts[1], "text": f"{parts[1]} is a hub: it changes with everything"})
    return chunks


def skill_files(repo: str) -> list[str]:
    out = []
    for base in (os.path.join(repo, ".claude", "skills"), repo):
        if not os.path.isdir(base):
            continue
        for name in sorted(os.listdir(base)):
            p = os.path.join(base, name, "SKILL.md")
            if os.path.isfile(p):
                out.append(os.path.relpath(p, repo))
    return out


# --- storage -----------------------------------------------------------------

SCHEMA = """
CREATE TABLE IF NOT EXISTS chunks (
  id INTEGER PRIMARY KEY, kind TEXT NOT NULL, path TEXT NOT NULL,
  start INTEGER, end INTEGER, symbol TEXT, text TEXT NOT NULL, embedding BLOB NOT NULL);
CREATE INDEX IF NOT EXISTS chunks_path ON chunks(path);
CREATE INDEX IF NOT EXISTS chunks_kind ON chunks(kind);
CREATE VIRTUAL TABLE IF NOT EXISTS fts USING fts5(symbol, path, text, id UNINDEXED, tokenize='unicode61');
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
"""


def connect(repo: str) -> sqlite3.Connection:
    con = sqlite3.connect(db_path(repo))
    con.executescript(SCHEMA)
    return con


def meta_get(con, key, default=None):
    row = con.execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return row[0] if row else default


def meta_set(con, key, value):
    con.execute("INSERT OR REPLACE INTO meta(key, value) VALUES (?, ?)", (key, value))


def delete_paths(con, paths):
    for p in paths:
        con.execute("DELETE FROM fts WHERE id IN (SELECT id FROM chunks WHERE path=?)", (p,))
        con.execute("DELETE FROM chunks WHERE path=?", (p,))


def insert_chunks(con, emb, chunks):
    for c in chunks:
        # Symbol tokens go in front so a name search hits even if the body is long.
        vec = emb.embed(" ".join(tokens(c["symbol"]) * 3) + " " + c["text"])
        cur = con.execute(
            "INSERT INTO chunks(kind, path, start, end, symbol, text, embedding) VALUES (?,?,?,?,?,?,?)",
            (c["kind"], c["path"], c["start"], c["end"], c["symbol"], c["text"], pack(vec)))
        con.execute("INSERT INTO fts(symbol, path, text, id) VALUES (?,?,?,?)",
                    (" ".join(tokens(c["symbol"])) + " " + c["symbol"], c["path"],
                     c["text"], cur.lastrowid))


def index_files(con, emb, repo: str, rels: list[str]) -> int:
    n = 0
    delete_paths(con, rels)
    for rel in rels:
        full = os.path.join(repo, rel)
        if not os.path.isfile(full):
            continue  # deleted: rows are gone already
        text = read_text(full)
        if text is None:
            continue
        chunks = chunk_code(rel, text)
        insert_chunks(con, emb, chunks)
        n += len(chunks)
    return n


def index_state(con, emb, repo: str) -> int:
    """Decisions, questions, skills and co-change pairs. Cheap, always refreshed."""
    sd = sweep_dir(repo)
    n = 0
    for fname, kind in (("decisions.md", "decision"), ("next-prompt.md", "question")):
        p = os.path.join(sd, fname)
        rel = os.path.relpath(p, repo)
        delete_paths(con, [rel])
        text = read_text(p)
        if text:
            chunks = chunk_markdown(rel, text, kind)
            insert_chunks(con, emb, chunks)
            n += len(chunks)
    for rel in skill_files(repo):
        delete_paths(con, [rel])
        text = read_text(os.path.join(repo, rel))
        if text:
            skill = os.path.basename(os.path.dirname(rel))
            chunks = chunk_markdown(rel, text, "skill", prefix=skill + ": ")
            insert_chunks(con, emb, chunks)
            n += len(chunks)
    delete_paths(con, ["cochange.tsv"])
    chunks = chunk_cochange(os.path.join(sd, "cochange.tsv"))
    insert_chunks(con, emb, chunks)
    return n + len(chunks)


# --- commands ----------------------------------------------------------------

def cmd_build(args):
    repo = repo_root(args.repo)
    if os.path.exists(db_path(repo)):
        os.remove(db_path(repo))
    con, emb = connect(repo), embedder()
    files = tracked_code_files(repo)
    n = index_files(con, emb, repo, files)
    m = index_state(con, emb, repo)
    meta_set(con, "embedder", emb.name)
    meta_set(con, "dim", str(emb.dim))
    meta_set(con, "head", git(repo, "rev-parse", "HEAD").strip())
    con.commit()
    print(f"indexed {n} code chunks from {len(files)} files, {m} state chunks, embedder {emb.name}")


def changed_since_head(repo: str, head: str) -> list[str]:
    files = set()
    if head and git(repo, "cat-file", "-t", head).strip() == "commit":
        files.update(git(repo, "diff", "--name-only", head).splitlines())
    for line in git(repo, "status", "--porcelain").splitlines():
        files.add(line[3:].split(" -> ")[-1])
    return sorted(f for f in files if f)


def cmd_update(args):
    repo = repo_root(args.repo)
    if not os.path.exists(db_path(repo)):
        return cmd_build(args)
    con, emb = connect(repo), embedder()
    if meta_get(con, "embedder") != emb.name:
        print("embedder changed, rebuilding", file=sys.stderr)
        return cmd_build(args)
    globs = ignore_globs(repo)
    rels = args.files or changed_since_head(repo, meta_get(con, "head", ""))
    rels = [os.path.relpath(os.path.abspath(os.path.join(repo if not os.path.isabs(r) else "", r)), repo)
            for r in rels]
    rels = [r for r in rels if os.path.splitext(r)[1] in CODE_EXT and not ignored(r, globs)]
    n = index_files(con, emb, repo, rels)
    m = index_state(con, emb, repo)
    meta_set(con, "head", git(repo, "rev-parse", "HEAD").strip())
    con.commit()
    print(f"updated {len(rels)} files ({n} chunks), {m} state chunks")


def fts_query(q: str) -> str:
    toks = tokens(q)
    return " OR ".join(f'"{t}"' for t in toks) if toks else '""'


def cosine_rank(con, qvec, kind, prefix, limit):
    sql, params = "SELECT id, embedding FROM chunks", []
    where = []
    if kind:
        where.append("kind=?"); params.append(kind)
    if prefix:
        where.append("path LIKE ?"); params.append(prefix + "%")
    if where:
        sql += " WHERE " + " AND ".join(where)
    rows = con.execute(sql, params).fetchall()
    try:
        import numpy as np  # optional
        ids = [r[0] for r in rows]
        if not ids:
            return []
        mat = np.frombuffer(b"".join(r[1] for r in rows), dtype=np.float32).reshape(len(rows), -1)
        q = np.asarray(qvec, dtype=np.float32)
        scores = mat @ q
        order = np.argsort(-scores)[:limit]
        return [(ids[i], float(scores[i])) for i in order]
    except ImportError:
        scored = []
        for cid, blob in rows:
            v = unpack(blob)
            scored.append((cid, sum(a * b for a, b in zip(v, qvec))))
        scored.sort(key=lambda x: -x[1])
        return scored[:limit]


def cmd_search(args):
    repo = repo_root(args.repo)
    if not os.path.exists(db_path(repo)):
        raise SystemExit("no index yet: run index.py build")
    con, emb = connect(repo), embedder()
    pool = max(args.limit * 5, 25)
    sql = "SELECT fts.id FROM fts JOIN chunks ON chunks.id = fts.id WHERE fts MATCH ?"
    params = [fts_query(args.query)]
    if args.kind:
        sql += " AND chunks.kind=?"; params.append(args.kind)
    if args.path:
        sql += " AND chunks.path LIKE ?"; params.append(args.path + "%")
    sql += " ORDER BY bm25(fts) LIMIT ?"; params.append(pool)
    lexical = [r[0] for r in con.execute(sql, params).fetchall()]
    vector = cosine_rank(con, emb.embed(args.query), args.kind, args.path, pool)
    # Reciprocal rank fusion: robust to the two scores living on different scales.
    fused: dict[int, float] = {}
    for rank, cid in enumerate(lexical):
        fused[cid] = fused.get(cid, 0.0) + 1.0 / (60 + rank)
    for rank, (cid, _) in enumerate(vector):
        fused[cid] = fused.get(cid, 0.0) + 1.0 / (60 + rank)
    top = sorted(fused.items(), key=lambda x: -x[1])[:args.limit]
    results = []
    for cid, score in top:
        kind, path, start, end, symbol, text = con.execute(
            "SELECT kind, path, start, end, symbol, text FROM chunks WHERE id=?", (cid,)).fetchone()
        first = next((l.strip() for l in text.splitlines() if l.strip()), "")
        results.append({"score": round(score, 4), "kind": kind, "path": path, "start": start,
                        "end": end, "symbol": symbol, "snippet": first[:100]})
    if args.json:
        print(json.dumps(results, indent=1))
        return
    if not results:
        print("no results")
        return
    for r in results:
        loc = f"{r['path']}:{r['start']}-{r['end']}" if r["kind"] == "code" else f"{r['path']}:{r['start']}"
        print(f"{r['score']:.4f}  {r['kind']:<9}{loc}  {r['symbol']}\n{'':17}{r['snippet']}")


def cmd_status(args):
    repo = repo_root(args.repo)
    if not os.path.exists(db_path(repo)):
        print("no index")
        return
    con = connect(repo)
    for kind, n in con.execute("SELECT kind, COUNT(*) FROM chunks GROUP BY kind ORDER BY kind"):
        print(f"{kind:<10}{n}")
    print(f"embedder  {meta_get(con, 'embedder')}")
    print(f"head      {meta_get(con, 'head')}")
    print(f"db        {db_path(repo)}")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--repo", default=".", help="any path inside the repo")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("build").set_defaults(fn=cmd_build)
    u = sub.add_parser("update"); u.add_argument("files", nargs="*"); u.set_defaults(fn=cmd_update)
    s = sub.add_parser("search")
    s.add_argument("query")
    s.add_argument("--kind", choices=["code", "decision", "question", "skill", "cochange"])
    s.add_argument("--limit", type=int, default=10)
    s.add_argument("--path", help="only paths starting with this prefix")
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_search)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    args = p.parse_args(argv)
    args.fn(args)


if __name__ == "__main__":
    main()
