---
name: migrate-cc-command
description: Convert a Claude command into a Claude Code skill.
when-to-use:
- migrate cc command, convert command to skill, refactor command
- When porting legacy Claude commands
user_invocable: true
category: meta
---

Refactor the following Claude command into a new Claude Code skill: $ARGUMENTS

- Extract the main command logic and place it into a separate script file (e.g., `scripts/main.py`).
- Write a `SKILL.md` file that includes:
    - YAML frontmatter with a name, description, permissions, and when-to-use metadata.
    - Clear, step-by-step instructions for invoking the skill, referencing the script file with `{baseDir}` for portability.
- Include any templates or resources as needed in dedicated subfolders (e.g., `templates/`, `examples/`).
- Format everything following best practices for Claude Code skills.
- Ensure the resulting skill is ready to be placed in the `.claude/skills/{skill-name}/` folder so Claude agents can discover it globally.

After the new skill is in place and verified, **remove the legacy source command file** so it does not collide with the new skill. A command at `~/.claude/commands/<name>.md` and a skill at `~/.claude/skills/<name>/` of the same name both register as `/<name>`, so leaving the command behind makes the slash-command palette show the entry twice (once per source). Delete the migrated `~/.claude/commands/<name>.md` (back it up first, e.g. `cp -p` to `/tmp`, since it is the only copy). Skip deletion only if the command has no same-named skill after migration.

Paste in your command after this prompt and run the refactor.
