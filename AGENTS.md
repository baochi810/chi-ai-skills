# Conventions for authoring skills in this repo

Read this before creating or editing any skill. For the directory layout and install
instructions see [README.md](README.md); this file only records the rules that have already
been broken once.

## Rule 1 — No machine-local paths inside a skill

**Banned**: `~/Projects/...`, `/Users/<name>/...`, hostnames, or anything else that exists on
exactly one machine — including inside a sentence like "for the original, see …".

Why: this repo is **public** and gets installed onto several machines and several agents. A
local path both leaks your private directory layout and is useless to you the moment you sit
at a different machine — the agent reads it and goes hunting for a directory that isn't there.

If you need to point at a real example, copy the thing itself into the skill's `templates/` or
`reference/`, then reference it with a relative path (`templates/release.sh`). A skill must be
**self-contained**.

## Rule 2 — Every `.md` file tracked in git is written in English

No exceptions, and not just the frontmatter — the body too. This covers `SKILL.md`,
`commands/*.md`, `reference/*.md`, `README.md`, and this file.

It also covers every `description` field, wherever it lives:

- `description:` in `SKILL.md` frontmatter
- `description:` in `commands/*.md` frontmatter
- the plugin `description` and `metadata.description` in `.claude-plugin/marketplace.json`

Why: these files are **instructions an agent reads**, not documentation for humans. The
`description` matters most of all — it is the **only** thing an agent reads when deciding
whether to invoke a skill at all; the body is loaded only after that decision is made. English
matches triggers more reliably and is the `SKILL.md` ecosystem's convention.

## Rule 3 — Everything a skill writes to disk is English too

Not just the `.md` files: the `templates/` a skill copies into a project, the comments and
`echo`/`print` strings inside them, and any code a skill generates. A template is the thing an
agent reads and edits most, so a comment it can't parse is a comment that doesn't do its job.

The one deliberate exception is **conversation**: the report a skill gives at the end of a run
is written in the language the user is speaking. That is the line — **artifacts in English,
conversation in the user's language**.

Keep that distinction alive when translating. A sentence like "write the report in Vietnamese"
is an *instruction*: render the sentence in English, but leave what it asks for alone.
Translating the instruction's content changes what the skill *does*, not what language it is
*written in*.

## Also worth remembering

- `name:` in `SKILL.md` must **match the directory name** containing it.
- A new skill must be declared in `plugins[]` in `.claude-plugin/marketplace.json`, or Claude
  Code won't see it (the Skills CLI still will — easy to mistake for "done").
- Audit Rules 2 and 3 with `python3 scripts/check-md-language.py`. It flags every non-ASCII
  letter in every tracked file and exits non-zero, so a clean run means a clean repo. Anything
  it reports is an oversight — finish translating it.

  Don't replace it with a `grep` character range over accented letters: the shell's locale
  collation reorders the range, so it silently swallows `…`, `→` and `·`, and buries the real
  hits in noise. Matching on the Unicode category, as the script does, is the reliable way.
- Verify before committing: `python3 -m json.tool .claude-plugin/marketplace.json`, `bash -n`
  on the shell templates, and `npx skills add . --list` to confirm the CLI still sees the skill.
