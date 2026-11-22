"""Parse the YAML frontmatter of a SKILL.md.

Stdlib only, so this reads the YAML subset skills use in practice: scalars
(plain, quoted, block), lists and nested mappings. It is lenient where real
files are sloppy (an unquoted value may contain ": ") and every scalar stays
a string.
"""

import re
from dataclasses import dataclass

_KEY = re.compile(r"^([A-Za-z0-9_.-]+):(?:[ \t]+(.*))?$")
_TRAILING_COMMENT = re.compile(r"\s+#.*$")
_ESCAPES = {"n": "\n", "t": "\t", '"': '"', "\\": "\\"}
_BOM = chr(0xFEFF)


@dataclass
class Parsed:
    meta: dict | None
    body: str
    error: str | None


def parse(text: str) -> Parsed:
    text = text.removeprefix(_BOM).replace("\r\n", "\n")
    lines = text.split("\n")
    if lines[0].strip() != "---":
        return Parsed(None, text, "no-frontmatter")
    for end in range(1, len(lines)):
        if lines[end].strip() == "---":
            return Parsed(_mapping(lines[1:end]), "\n".join(lines[end + 1:]), None)
    return Parsed(None, text, "unterminated-frontmatter")


def _mapping(lines: list[str]) -> dict:
    result = {}
    i = 0
    while i < len(lines):
        match = _KEY.match(lines[i])
        i += 1
        if not match:
            continue
        inline = (match.group(2) or "").strip()
        start = i
        while i < len(lines) and _continues(lines[i], inline):
            i += 1
        result[match.group(1)] = _value(inline, lines[start:i])
    return result


def _continues(line: str, inline: str) -> bool:
    if not line.strip() or line[0] in " \t":
        return True
    return not inline and line.startswith("-")


def _value(inline: str, rest: list[str]):
    block = _dedent(rest)
    if inline[:1] in ("|", ">"):
        return _block_scalar(block, folded=inline[0] == ">")
    if inline.startswith("[") and inline.endswith("]"):
        return [_scalar(item) for item in inline[1:-1].split(",") if item.strip()]
    if inline:
        return _scalar(" ".join([inline, *(line.strip() for line in block if line.strip())]))
    content = [line for line in block if line.strip() and not line.lstrip().startswith("#")]
    if not content:
        return ""
    if content[0].startswith("-"):
        return [_scalar(line[1:]) for line in content if line.startswith("-")]
    if _KEY.match(content[0]):
        return _mapping(block)
    return _scalar(" ".join(line.strip() for line in content))


def _dedent(lines: list[str]) -> list[str]:
    indents = [len(line) - len(line.lstrip()) for line in lines if line.strip()]
    cut = min(indents, default=0)
    return [line[cut:] for line in lines]


def _block_scalar(lines: list[str], folded: bool) -> str:
    if not folded:
        return "\n".join(lines).strip("\n")
    paragraphs = "\n".join(lines).strip("\n").split("\n\n")
    return "\n".join(" ".join(part.split("\n")) for part in paragraphs)


def _scalar(raw: str) -> str:
    raw = raw.strip()
    if len(raw) >= 2 and raw[0] == raw[-1] == '"':
        return re.sub(r"\\(.)", lambda m: _ESCAPES.get(m.group(1), m.group(0)), raw[1:-1])
    if len(raw) >= 2 and raw[0] == raw[-1] == "'":
        return raw[1:-1].replace("''", "'")
    return _TRAILING_COMMENT.sub("", raw)
