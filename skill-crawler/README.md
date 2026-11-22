# Skill crawler

Finds public agent skills (`SKILL.md` files) on GitHub and records their metadata as JSON lines. Python 3.10+ standard library only; nothing to install. It is tooling, not a skill: the folder has no `SKILL.md`, so the sync and the Copilot plugin check ignore it.

## Run

```bash
cd skill-crawler
```

Crawl from [`seeds.txt`](seeds.txt) and write a fresh dataset to `data/` (ignored by git):

```bash
python3 -m skill_crawler crawl
```

Summarize the dataset:

```bash
python3 -m skill_crawler report
```

List skills whose name or description contains every term, most-starred repositories first:

```bash
python3 -m skill_crawler find pull request review
```

Options for `crawl`: `--max-repos` (default 300), `--max-depth` (default 1), `--search-pages` (default 1, 100 repositories each), `--delay` (default 1.0 s between requests to one host), `--seeds`, `--out`.

## How it crawls

1. **Seeds** (`seeds.txt`, one per line): a GitHub repository URL, any other `https` page, or `search:<query>` for the GitHub repository search API (most starred first).
2. **Discovery.** Page and search seeds are expanded first. Repositories are then scanned breadth-first in the order found, until `--max-repos`. A scanned repository's README adds the repositories it links to, one level deeper, up to `--max-depth`. A repository is scanned once per run.
3. **Scan.** One request per repository: its default-branch archive from `codeload.github.com`, read as a stream. Each `SKILL.md` becomes one line in `data/skills.jsonl`; each repository becomes one line in `data/repos.jsonl`.

## What it will and will not do

- **No credentials.** No token is read or sent, so only public data is reachable and GitHub's unauthenticated limits apply (search: 10 requests a minute, paced at one per 6.5 s).
- **Polite.** One connection per host, a delay between requests, a fixed generic `User-Agent`, `robots.txt` honored on every host including redirect targets. `https` only.
- **Archives are untrusted input.** Nothing is extracted to disk. Only regular files named `SKILL.md` and the root README are read, 256 KB each at most; symlinks are skipped; the stream is cut at 30 MB (`truncated: true` in `repos.jsonl`).
- **Stores metadata, not skills.** Frontmatter fields, sizes and a hash of the body are kept; the skill text is not.
- **A cut download is an error.** A reply shorter than its declared length is recorded as `status: error`, never as a complete archive.

## Records

`skills.jsonl`, one line per `SKILL.md`:

| Field | Meaning |
|---|---|
| `id`, `repo`, `path`, `commit`, `url` | Where the skill lives; `url` is pinned to the scanned commit |
| `name`, `description`, `license`, `allowed_tools`, `frontmatter_keys` | Frontmatter as written |
| `problems` | Rules of the [Agent Skills specification](https://agentskills.io/specification) the frontmatter breaks: `no-frontmatter`, `unterminated-frontmatter`, `missing-name`, `name-invalid`, `name-too-long`, `name-dir-mismatch`, `missing-description`, `description-invalid`, `description-too-long`, `compatibility-too-long` |
| `body_bytes`, `body_lines`, `body_sha256` | Size of the instructions and a hash that is equal for copies |
| `file_count`, `has_scripts` | Files bundled in the skill folder; whether it has a `scripts/` folder |
| `via`, `depth` | How the repository was found |
| `repo_stars`, `repo_license`, `repo_pushed_at` | Known only for repositories that a search seed returned |
| `fetched_at` | UTC time of the scan |

`repos.jsonl`, one line per scanned repository: `repo`, `status` (`ok`, `http-<code>`, `error`, `bad-archive`, `robots-disallowed`), `commit`, `skills`, `truncated`, `depth`, `via`, `stars`, `license`, `pushed_at`, `fetched_at`.

## Limits

- Stars and repository license come from search results only. Repositories reached through a README link have them empty.
- GitHub code search (`filename:SKILL.md`) would find skills in repositories that no list or topic mentions, but it requires a token, which this crawler does not use.
- The frontmatter reader covers the YAML that skills use (scalars, block scalars, lists, one level of mapping), not all of YAML.
- `urllib.robotparser` matches path prefixes; it does not expand `*` wildcards inside robots rules.

## Tests

No network; a canned transport and a scripted socket stand in for it. From the repository root:

```bash
python3 -m unittest discover -s skill-crawler/tests -t skill-crawler
```
