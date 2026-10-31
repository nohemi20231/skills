# Third-party skills

Skills by other authors that I use. They are not stored or redistributed in this repo;
I keep local copies only (in `~/.claude/skills/` or as installed plugins), each with its
upstream license. This list credits the authors and records where each one comes from.

| Skill | Author | Source | License | Version | Local changes |
|---|---|---|---|---|---|
| `test-driven-development` | Jesse Vincent (`obra`) | [obra/superpowers](https://github.com/obra/superpowers), `skills/test-driven-development/` | MIT | commit `2ce8aa15d05bd57213e6f746f953aafb7ded7a8b` (2026-10-21) | One cross-reference to another superpowers skill reworded so the folder stands alone |
| `document-specialist` plugin (`write-architecture`, `write-design-doc`, `write-sdd`, `write-wireframe`, `documentation-specialist`) | Rick Hightower (`SpillwaveSolutions`) | [SpillwaveSolutions/document-specialist-skill](https://github.com/SpillwaveSolutions/document-specialist-skill) | MIT (declared in `plugin.json`) | 3.3.0 | None |

## Install

`test-driven-development`, as part of the full superpowers plugin:

```
/plugin install superpowers@claude-plugins-official
```

Or copy just the folder from upstream into `~/.claude/skills/test-driven-development/` and keep its `LICENSE`.

`document-specialist`:

```
/plugin marketplace add SpillwaveSolutions/document-specialist-skill
/plugin install document-specialist@spillwave-document-specialist
```
