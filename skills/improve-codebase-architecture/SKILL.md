---
name: improve-codebase-architecture
description: Find module-deepening refactor opportunities for testability and AI-navigability.
when-to-use:
- improve architecture, find refactoring opportunities, deepen modules
- Consolidating tightly-coupled modules; making a codebase more testable
permissions:
- read
- write
- bash
category: code
related-skills:
- diagnose
- refactor
- simplify
---

# Improve Codebase Architecture

Surface architectural friction and propose **deepening opportunities** — refactors that turn shallow modules into deep ones. The aim is testability and AI-navigability.

## Glossary

Use these terms exactly in every suggestion. Consistent language is the point — don't drift into "component," "service," "API," or "boundary." Full definitions in [LANGUAGE.md](LANGUAGE.md).

- **Module** — anything with an interface and an implementation (function, class, package, slice).
- **Interface** — everything a caller must know to use the module: types, invariants, error modes, ordering, config. Not just the type signature.
- **Implementation** — the code inside.
- **Depth** — leverage at the interface: a lot of behaviour behind a small interface. **Deep** = high leverage. **Shallow** = interface nearly as complex as the implementation.
- **Seam** — where an interface lives; a place behaviour can be altered without editing in place. (Use this, not "boundary.")
- **Adapter** — a concrete thing satisfying an interface at a seam.
- **Leverage** — what callers get from depth.
- **Locality** — what maintainers get from depth: change, bugs, knowledge concentrated in one place.

Key principles (see [LANGUAGE.md](LANGUAGE.md) for the full list):

- **Deletion test**: imagine deleting the module. If complexity vanishes, it was a pass-through. If complexity reappears across N callers, it was earning its keep.
- **The interface is the test surface.**
- **One adapter = hypothetical seam. Two adapters = real seam.**

If the repo keeps a domain glossary (`CONTEXT.md`) or ADRs (`docs/adr/`), this skill is _informed_ by them: the domain language gives names to good seams; ADRs record decisions the skill should not re-litigate. If neither exists, proceed without — and create them lazily during the grilling loop (step 3).

## Process

### 1. Explore

Read the project's domain glossary and any ADRs in the area you're touching first, if they exist.

Then use the Agent tool with `subagent_type=Explore` to walk the codebase. Don't follow rigid heuristics — explore organically and note where you experience friction:

- Where does understanding one concept require bouncing between many small modules?
- Where are modules **shallow** — interface nearly as complex as the implementation?
- Where have pure functions been extracted just for testability, but the real bugs hide in how they're called (no **locality**)?
- Where do tightly-coupled modules leak across their seams?
- Which parts of the codebase are untested, or hard to test through their current interface?

Apply the **deletion test** to anything you suspect is shallow: would deleting it concentrate complexity, or just move it? A "yes, concentrates" is the signal you want.

### 2. Present candidates as an HTML report

Write a self-contained HTML file to the OS temp directory so nothing lands in the repo: `${TMPDIR:-/tmp}/architecture-review-<timestamp>.html`. Open it for the user (`open <path>` on macOS, `xdg-open` on Linux) and tell them the absolute path.

The report uses **Tailwind via CDN** and **Mermaid via CDN** for graph-shaped diagrams (call graphs, dependencies, sequences); hand-built divs/SVG for editorial visuals. Each candidate gets a **before/after visualisation**. See [HTML-REPORT.md](HTML-REPORT.md) for the full scaffold and styling guidance.

Each candidate card:

- **Files** — which files/modules are involved
- **Problem** — why the current architecture is causing friction
- **Solution** — plain English description of what would change
- **Benefits** — explained in terms of locality and leverage, and how tests would improve
- **Before / After diagram** — side-by-side, illustrating the shallowness and the deepening
- **Recommendation strength** — `Strong`, `Worth exploring`, or `Speculative`, rendered as a badge

End with a **Top recommendation** section: which candidate you'd tackle first and why.

**Use the project's domain vocabulary for the domain, and [LANGUAGE.md](LANGUAGE.md) vocabulary for the architecture.** If the glossary defines "Order," talk about "the Order intake module" — not "the FooBarHandler."

**ADR conflicts**: if a candidate contradicts an existing ADR, only surface it when the friction is real enough to warrant revisiting the ADR. Mark it clearly in the card. Don't list every theoretical refactor an ADR forbids.

Do NOT propose interfaces yet. After the file is written, ask the user: "Which of these would you like to explore?"

### 3. Grilling loop

Once the user picks a candidate, drop into a grilling conversation. Walk the design tree with them — constraints, dependencies, the shape of the deepened module, what sits behind the seam, what tests survive. For dependency classification and safe-deepening mechanics, see [DEEPENING.md](DEEPENING.md).

Side effects happen inline as decisions crystallize:

- **Naming a deepened module after a concept not in the glossary?** Add the term to `CONTEXT.md` using [CONTEXT-FORMAT.md](CONTEXT-FORMAT.md). Create the file lazily if it doesn't exist.
- **Sharpening a fuzzy term during the conversation?** Update `CONTEXT.md` right there.
- **User rejects the candidate with a load-bearing reason?** Offer an ADR: _"Want me to record this as an ADR so future architecture reviews don't re-suggest it?"_ Only when the reason would actually be needed by a future explorer — skip ephemeral ("not worth it right now") and self-evident reasons. See [ADR-FORMAT.md](ADR-FORMAT.md).
- **Want to explore alternative interfaces for the deepened module?** See [INTERFACE-DESIGN.md](INTERFACE-DESIGN.md) — parallel sub-agents, each with a radically different design constraint.

## Scope note

This is codebase-scoped architecture work. For change-scoped cleanup of a recent diff, use `refactor` or `simplify` instead. `diagnose` hands off here when a bug reveals a missing test seam.
