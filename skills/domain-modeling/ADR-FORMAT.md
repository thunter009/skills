# ADR Format

ADRs live in `docs/adr/` with sequential numbering: `0001-slug.md`, `0002-slug.md`, etc. Create the `docs/adr/` directory lazily — only when the first ADR is needed.

## Template

```md
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

That's it. An ADR can be a single paragraph. The value is recording *that* a decision was made and *why* — not filling out sections.

## Optional sections

Only include these when they add genuine value; most ADRs won't need them.

- **Status** frontmatter (`proposed | accepted | deprecated | superseded by ADR-NNNN`) — useful when decisions get revisited.
- **Considered Options** — only when the rejected alternatives are worth remembering.
- **Consequences** — only when non-obvious downstream effects need calling out.

## Numbering

Scan `docs/adr/` for the highest existing number and increment by one.

## When to offer an ADR

All three must be true:

1. **Hard to reverse** — the cost of changing your mind later is meaningful.
2. **Surprising without context** — a future reader will look at the code and wonder "why on earth did they do it this way?"
3. **The result of a real trade-off** — there were genuine alternatives and you picked one for specific reasons.

Easy to reverse? Skip it — you'll just reverse it. Not surprising? Nobody will wonder why. No real alternative? Nothing to record beyond "we did the obvious thing."

### What qualifies

- **Architectural shape.** "Monorepo." "Write model is event-sourced, read model projected into Postgres."
- **Integration patterns between contexts.** "Ordering and Billing communicate via domain events, not synchronous HTTP."
- **Technology choices that carry lock-in.** Database, message bus, auth provider, deployment target — the ones that'd take a quarter to swap, not every library.
- **Boundary and scope decisions.** "Customer data is owned by the Customer context; other contexts reference it by ID only." The explicit no's are as valuable as the yes's.
- **Deliberate deviations from the obvious path.** "Manual SQL instead of an ORM because X." Anything where a reasonable reader would assume the opposite — stops the next engineer from "fixing" a deliberate choice.
- **Constraints not visible in the code.** "Can't use AWS because of compliance." "Response times must be under 200ms because of the partner API contract."
- **Rejected alternatives when the rejection is non-obvious.** Considered GraphQL, picked REST for subtle reasons — record it, or someone suggests GraphQL again in six months.
