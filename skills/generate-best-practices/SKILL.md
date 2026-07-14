---
name: generate-best-practices
description: Generate a concise best-practices guide for the current stack.
when-to-use:
- generate best practices, stack guide, framework guide
- When a repo needs agent-facing conventions
user_invocable: true
allowed-tools: Bash|Read|Write|Glob|Grep|Agent
category: code
---

Generate a concise best-practice guide for the current project's stack and save it to `docs/best-practices.md` (or `docs/best-practices-<framework>.md` if multiple frameworks).

**Step 1 -- Detect stack:**
Read AGENTS.md, CLAUDE.md, package.json/pyproject.toml/Cargo.toml to identify:
- Language + version
- Framework(s) + version
- Key libraries
- Test runner
- Linter

**Step 2 -- Generate guide:**
For each major framework/library, write a concise best-practice guide covering:
- Project structure conventions
- Common patterns (with code examples)
- Performance gotchas
- Security considerations
- Testing patterns
- Common mistakes to avoid
- Version-specific features to prefer (e.g., React 19 use() hook, Python 3.12+ type syntax)

**Step 3 -- Reference from AGENTS.md:**
Add a line to the project's AGENTS.md pointing to the guide:
```markdown
## Best Practices
See [docs/best-practices.md](docs/best-practices.md) for stack-specific guidelines.
```

**Constraints:**
- Keep each guide under 200 lines -- concise, not exhaustive
- Focus on what agents get wrong, not comprehensive tutorials
- Use the project's actual patterns as examples where possible
- $ARGUMENTS can specify a framework to focus on (e.g., "nextjs" or "dagster")
