---
name: wayfinder
description: Plan a chunk of work too big for one agent session by charting it as a map of investigation/decision tickets in beads — resolve them one at a time until the route to the destination is clear, then hand off to execution. Use for foggy, ambitious efforts where the way from here to done isn't visible yet.
when-to-use:
- plan work bigger than one session where the path is unclear (a spec, a migration, a decision to lock)
- chart this, wayfind this, map out this big fuzzy piece of work
- when you'd otherwise charge at a destination you can't yet see
allowed-tools:
- Bash
- Read
- Grep
- Glob
- AskUserQuestion
category: pm
---

# Wayfinder

A loose, ambitious idea has arrived — too big for one agent session, wrapped in fog: the way from here to the **destination** isn't visible yet. Wayfinding is about finding that way, not charging at the destination. This skill charts the way as a **map of decision tickets in beads**, then resolves them one at a time until the route is clear — at which point you **hand off to execution** (`route-build-mode` / [`swarm-start`](../swarm-start/SKILL.md) / `swarm-build`).

**This is a planning skill, not a competing planner.** It ends where those skills begin: it produces a resolved set of decisions, not the deliverable. The pull to just do the work is usually the signal you've reached the edge of the map — time to hand off.

## Plan, don't do

Each ticket resolves a **decision or investigation**, not a chunk of the deliverable. The map is done when nothing is left to decide before someone goes and builds the thing. Produce decisions, not code.

## The map — expressed in beads

- **The map** is a beads **epic**, tagged so it's findable: `br create --type epic --labels wayfinder:map "<destination name>"`. Its body (the description) holds Destination / Notes / Decisions-so-far / Not-yet-specified / Out-of-scope (structure below).
- **Tickets** are child beads of the map: `br create --parent <map-id> --labels wayfinder:<type> "<question>"` (the `--parent` flag creates the parent-child dep). Wire blocking edges between siblings with `br dep add <ticket> <blocker>`.
- **The frontier** — open, unblocked, unclaimed tickets — is one query: `br ready --parent <map-id> --unassigned`. `br ready` already means open-and-unblocked; `--parent` scopes to everything beneath the map epic; `--unassigned` drops claimed tickets. That's the edge of the known.
- **Claim** a ticket before working it: `br update <id> --assignee <you>` — an atomic claim that sets assignee + `status=in_progress` in one op, so it drops out of the `--unassigned` frontier and concurrent sessions skip it.

Refer to tickets **by title**, never a bare id — a wall of `bd-1a, bd-2b, bd-3c` is illegible; names read at a glance.

### Map body structure

```markdown
## Destination
<what reaching the end looks like — the spec, decision, or change this effort finds its way to. One or two lines.>

## Notes
<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far
<!-- index: one line per closed ticket -->
- <closed ticket title> (bd-xx) — <one-line gist of the answer>

## Not yet specified
<!-- fog: in-scope questions you can't sharply phrase yet; graduate into tickets as the frontier advances -->

## Out of scope
<!-- work consciously ruled beyond the destination; closed, never graduates -->
```

## Ticket types

Every ticket is **HITL** (human-in-the-loop, worked *with* a human) or **AFK** (agent alone). A HITL ticket only resolves through live exchange — never answer the human's side for them.

- **Grilling** (HITL, the default) — resolve a decision via the [`grilling`](../grilling/SKILL.md) + [`domain-modeling`](../domain-modeling/SKILL.md) loop, one question at a time.
- **Research** (AFK) — read docs / APIs / local knowledge; capture a markdown summary linked from the ticket. Use the repo's web-research scripts.
- **Prototype** (HITL) — make a cheap concrete artifact to react to (outline, stub, UI/logic via [`prototype`](../prototype/SKILL.md)) when "how should it look/behave" is the question.
- **Task** (HITL or AFK) — manual work that must happen before a *decision* can be made (provision access, move data so its shape is visible). The one type that *does* rather than decides, and it earns its place only by unblocking a decision.

## Fog of war

The map is deliberately incomplete — don't chart what you can't yet see. Beyond the live tickets is the **fog**: decisions you can tell are coming but can't yet phrase sharply. Write them loosely under **Not yet specified**. Resolving a ticket clears the fog ahead of it, graduating whatever's now sharp into fresh tickets — one at a time, until no tickets remain.

**Ticket or fog?** The test is whether you can *state the question precisely now* — not whether you can answer it. Sharp question (even if blocked) → ticket. Can't phrase it sharply yet → Not yet specified. Don't pre-slice the fog.

**Out of scope** is different: work beyond the destination. It's not fog and never graduates; it returns only if the destination is redrawn.

## Invocation

**Never resolve more than one ticket per session.**

### Chart the map (user arrives with a loose idea)
1. **Name the destination** via a `grilling` + `domain-modeling` session — it fixes the scope, so settle it first.
2. **Map the frontier** — grill again, breadth-first, surfacing the open decisions and first takeable steps. If this surfaces *no* fog (the way is already clear, small enough for one session), you don't need a map — stop and ask how they want to proceed.
3. **Create the map epic** — Destination + Notes filled, Decisions-so-far empty, fog sketched into Not-yet-specified.
4. **Create the tickets you can specify now** as child beads, then wire blocking edges in a **second pass** (`br dep add`; beads need ids before they can reference each other).
5. Stop — charting is one session's work. Don't also resolve tickets.

### Work through the map (user arrives with a map)
1. Load the **map body** — the low-res view, not every ticket.
2. Choose the ticket: the one the user named, else the first frontier ticket from `br ready --parent <map-id> --unassigned`. **Claim it** (`br update <id> --assignee <you>`).
3. Resolve it — zoom into related/closed tickets on demand (`br show <id>`); invoke the skills the Notes block names; default to `grilling` + `domain-modeling`.
4. Record: post the answer with `br comments <id> add`, `br close <id>`, and append a one-line pointer to the map's Decisions-so-far.
5. Graduate any fog the answer sharpened into new tickets (create-then-wire); if the answer reveals a ticket sits beyond the destination, rule it out of scope (close it, one line under Out-of-scope) rather than resolving it.
6. **When the frontier is empty and no fog remains, the map is done** — the route is clear. Hand off to `route-build-mode` to pick execution mode, then the relevant build skill. Don't roll into building inside the same session.

Remember to `br sync --flush-only && git add .beads/ && git commit` so the map and tickets are shared.

## Related skills

- [`grilling`](../grilling/SKILL.md) / [`domain-modeling`](../domain-modeling/SKILL.md) — the resolution loop for most tickets.
- `route-build-mode` — the handoff target once the route is clear.
- [`beads-linear-sync`](../beads-linear-sync/SKILL.md) — mirror the map to Linear if humans need a UI.
