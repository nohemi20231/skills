"""Command line: crawl, report, find."""

import argparse
import json
import sys
from pathlib import Path

from .crawl import crawl, parse_seeds
from .fetch import Fetcher
from .report import find, summarize

_HOME = Path(__file__).resolve().parent.parent
_SEARCH_API_DELAY = 6.5  # GitHub allows 10 unauthenticated search requests a minute


class _UsageError(Exception):
    pass


def main(argv=None, *, fetcher=None, out=sys.stdout, err=sys.stderr) -> int:
    args = _parser().parse_args(argv)
    try:
        return args.command(args, fetcher, out, err)
    except _UsageError as error:
        print(f"skill-crawler: {error}", file=err)
        return 2


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="skill_crawler", description=__doc__)
    commands = parser.add_subparsers(required=True)

    run = commands.add_parser("crawl", help="crawl from the seeds and write a fresh dataset")
    run.add_argument("--seeds", default=_HOME / "seeds.txt", help="seed list (default: seeds.txt)")
    run.add_argument("--out", default=_HOME / "data", help="dataset folder (default: data/)")
    run.add_argument("--max-repos", type=int, default=300, help="repositories to scan at most")
    run.add_argument("--max-depth", type=int, default=1, help="link levels to follow from the seeds")
    run.add_argument("--search-pages", type=int, default=1, help="result pages per search seed, 100 each")
    run.add_argument("--delay", type=float, default=1.0, help="seconds between requests to one host")
    run.set_defaults(command=_crawl)

    report = commands.add_parser("report", help="summarize the dataset")
    report.add_argument("--data", default=_HOME / "data")
    report.set_defaults(command=_report)

    search = commands.add_parser("find", help="list skills whose name or description has every term")
    search.add_argument("--data", default=_HOME / "data")
    search.add_argument("--limit", type=int, default=20)
    search.add_argument("terms", nargs="+")
    search.set_defaults(command=_find)
    return parser


def _crawl(args, fetcher, out, err) -> int:
    try:
        seeds = parse_seeds(Path(args.seeds).read_text().splitlines())
    except (OSError, ValueError) as error:
        raise _UsageError(error) from error
    fetcher = fetcher or Fetcher(
        delay=args.delay, host_delays={"api.github.com": max(args.delay, _SEARCH_API_DELAY)}
    )
    folder = Path(args.out)
    folder.mkdir(parents=True, exist_ok=True)
    counts = {"skills": 0, "repos": 0}
    with open(folder / "skills.jsonl", "w") as skills, open(folder / "repos.jsonl", "w") as repos:
        def writer(stream, kind):
            def write(record):
                stream.write(json.dumps(record, ensure_ascii=False) + "\n")
                stream.flush()
                counts[kind] += 1
            return write

        crawl(seeds, fetcher, on_skill=writer(skills, "skills"), on_repo=writer(repos, "repos"),
              max_repos=args.max_repos, max_depth=args.max_depth, search_pages=args.search_pages,
              log=lambda line: print(line, file=err, flush=True))
    print(f"wrote {counts['skills']} skills from {counts['repos']} repositories to {folder}", file=out)
    return 0


def _report(args, fetcher, out, err) -> int:
    summary = summarize(*_load(args.data))
    lines = [
        f"repositories scanned: {summary['repos_scanned']} "
        f"({summary['repos_with_skills']} with skills, {summary['repos_truncated']} truncated)",
        f"repository status: {_pairs(summary['repo_status'])}",
        f"repository licenses: {_pairs(summary['repo_licenses'])}",
        f"skills: {summary['skills']} ({summary['unique_bodies']} unique bodies, "
        f"{summary['skills_copied_across_repos']} copied across repositories)",
        f"spec conforming: {summary['spec_conforming']} of {summary['skills']}",
        f"problems: {_pairs(summary['problems'])}",
        f"with scripts: {summary['with_scripts']}, with allowed-tools: "
        f"{summary['with_allowed_tools']}, with license field: {summary['with_license_field']}",
        f"extra frontmatter keys: {_pairs(dict(list(summary['extra_frontmatter_keys'].items())[:15]))}",
        f"median body lines: {summary['median_body_lines']}, "
        f"median description chars: {summary['median_description_chars']}",
        "top repositories by skill count:",
        *(f"  {repo}: {count} skills, {_stars(stars)}" for repo, count, stars in summary["top_repos"]),
    ]
    print("\n".join(lines), file=out)
    return 0


def _find(args, fetcher, out, err) -> int:
    skills, _ = _load(args.data)
    matches = find(skills, args.terms)
    for skill in matches[:args.limit]:
        print(f"{skill['repo']}  {skill['name']}  ({_stars(skill['repo_stars'])})", file=out)
        print(f"  {(skill['description'] or '')[:200]}", file=out)
        print(f"  {skill['url']}", file=out)
    print(f"{len(matches)} matches", file=out)
    return 0


def _load(folder) -> tuple[list[dict], list[dict]]:
    try:
        return tuple(
            [json.loads(line) for line in (Path(folder) / name).read_text().splitlines()]
            for name in ("skills.jsonl", "repos.jsonl")
        )
    except OSError as error:
        raise _UsageError(f"no dataset in {folder}; run the crawl command first") from error


def _pairs(counts: dict) -> str:
    return ", ".join(f"{key} {value}" for key, value in counts.items()) or "none"


def _stars(stars) -> str:
    return "stars unknown" if stars is None else f"{stars} stars"
