# chi-ai-skills

Shared skills for AI coding agents. Each skill is a directory holding a `SKILL.md`, following
the [Agent Skills](https://github.com/anthropics/skills) convention — the same files work in
Claude Code, Codex, Cursor, Gemini CLI, and any other agent that reads `SKILL.md`.

## Available skills

| Skill | What it does |
|---|---|
| [`core-scripts-setup`](skills/core-scripts-setup/) | Scaffolds `run.sh` + `release.sh` + local install + auto-update infrastructure over GitHub Releases, for a project in any language. Ships templates that have run in production for macOS `.app` install/self-update. |

## Install

### Skills CLI — recommended, works with any agent

```bash
npx skills add baochi810/chi-ai-skills      # install (auto-detects the agents you have)
npx skills update                            # update
npx skills add baochi810/chi-ai-skills -g    # install globally instead of per-project
```

### Claude Code — via the plugin marketplace

```
/plugin marketplace add baochi810/chi-ai-skills
/plugin install core-scripts@chi-ai-skills
```

Update with `/plugin marketplace update chi-ai-skills`.

### By hand

Copy the skill directory wherever your agent looks for it:

```bash
git clone git@github.com:baochi810/chi-ai-skills.git
cp -R chi-ai-skills/skills/core-scripts-setup ~/.claude/skills/    # Claude Code
cp -R chi-ai-skills/skills/core-scripts-setup ~/.codex/skills/     # Codex
cp -R chi-ai-skills/skills/core-scripts-setup ~/.cursor/skills/    # Cursor
```

## Adding a new skill

1. Create `skills/<kebab-case-name>/SKILL.md`. Minimum frontmatter:

   ```yaml
   ---
   name: kebab-case-name         # must match the directory name
   description: What it does + WHEN to use it. This line is all an agent reads to decide
                whether to invoke the skill.
   version: 0.1.0
   ---
   ```

2. Put supporting files next to `SKILL.md`. The convention here: `templates/` (files meant to
   be copied into a project), `reference/` (further reading, loaded on demand), `scripts/`.
3. Optionally add a slash command at `commands/<name>.md`.
4. Declare the skill in `plugins[]` in `.claude-plugin/marketplace.json`. The Skills CLI does
   not require that file, but Claude Code needs it to surface the skill under `/plugin`.

The flat `skills/<name>/SKILL.md` layout at the repo root is what the Skills CLI scans — don't
nest it any deeper.

Before writing a skill, read [AGENTS.md](AGENTS.md) for the authoring rules.

## License

[MIT](LICENSE)
