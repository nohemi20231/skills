# Skills

Claude Code skills, one folder per skill, each with a `SKILL.md`.

| Skill | What it does |
|---|---|
| `research-approve-build-verify/` | Adds a feature to an existing app: parallel read-only research, design approval gate, TDD build, fresh-context QA, evidence report. |

## Install

Link a skill into Claude Code so it's available in every project:

```bash
mkdir -p ~/.claude/skills
ln -s ~/workspace/agents/skills/research-approve-build-verify ~/.claude/skills/research-approve-build-verify
```

Restart Claude Code, then run `/research-approve-build-verify`.
