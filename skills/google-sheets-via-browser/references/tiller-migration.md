# Tiller Money migration playbook

Applies the parent skill's browser-driving techniques to the specific,
recurring task of migrating or consolidating a Tiller Money Google Sheet
(e.g. moving from an old Tiller Foundation template to a new one, or
merging two Tiller sheets).

## A "new sheet" is not a migration

Creating a new Tiller Foundation sheet and letting the feed fill it in is
**not** a migration — it re-pulls the entire feed history from scratch and
every transaction lands **UNCATEGORIZED**. Everything a user actually cares
about — categorization, tags, splits, statement links, manual overrides —
lives only in the old sheet's `Transactions` tab and is not reconstructible
from the raw feed.

Tiller's own built-in migration tool copies **Categories** and **Saved
Splits**, and *possibly* a copy of **AutoCat** — but check the rule count
before trusting it, because the copy can be silently **truncated** relative
to the source. It copies **none** of: transaction categorization, Balance
History depth, or budget history. Do not assume "I ran Tiller's migration"
means the new sheet is usable day-to-day.

## Minimum viable port for day-to-day continuity

To make the new sheet a real replacement (not just a feed forwarder), port
these tabs from the old sheet into the new sheet's matching tabs, using the
parent skill's **clear-existing-tab-then-paste** technique (never
delete/recreate — see the cardinal rule) so the feed keeps appending
correctly afterward:

- `Transactions` — the categorized history, not just the raw feed rows.
- `AutoCat` — the **full** rule set, not whatever (possibly truncated)
  subset Tiller's migration copied.
- `Categories` — including any custom `Tags`/`Track` columns the user added.
- `Balance History` — full depth; Tiller's migration typically doesn't
  carry this over at all.
- `Valid Tags` (or equivalent lookup tab, naming varies by template
  generation).

Transplant data **into** the new sheet's existing template tabs (clear +
paste), not as new tabs — this preserves the feed binding on `Transactions`
and keeps formula references in report tabs intact.

## Column schema differences between generations

Older Tiller templates and newer ones use different `Transactions` column
sets:

- Old: `Statement`, `Transaction ID`, `Metadata`, `Tags`, `Group`.
- New: `Category Hint`, `Categorized By`, `Source`.

Tiller adapts to whatever header row it finds — extra columns beyond what
the new template expects are fine and won't break the feed. Don't try to
force column-for-column parity; just make sure the columns the new
template's formulas actually depend on (category, amount, date, account)
are present and correctly named.

## Budget/Categories flatten-before-trim sequence

The `Categories` tab's month headers are chained `EOMONTH` formulas, and
individual budget cells are frequently **live lookups into a separate
`Budget Builder` tab** rather than static numbers. This interacts badly
with trimming history:

1. **Flatten first**: paste-special-values the budget cells in the OLD
   sheet (where the `Budget Builder` lookups still resolve correctly) to
   freeze them as static numbers — using the "copy from where it resolves,
   paste-values at the destination" technique from the values-flatten trap
   in the parent skill.
2. **Only then** trim old history columns, or port into the new sheet.
   Trimming columns before flattening risks knocking out the lookup chain
   and silently zeroing budget values (same iferror-fallback trap as any
   other cross-sheet formula port).
3. Port the now-static budget **values** from the old sheet into the new
   one — not the formulas, which would re-break against the new sheet's
   (different) `Budget Builder` tab or lack one entirely.

## Simultaneous feeds during cutover

Both the old and new sheets can receive live feed updates at the same time
if they're both still linked to the same accounts in Tiller Console. To
know which sheet is actually ahead / current:

- Compare the latest transaction date in each sheet's `Transactions` tab.
- Whichever is later is the one that's been receiving fresher feed data.

Once cutover is confirmed (new sheet has the ported history AND is
receiving feed updates), **remind the user to unlink the old sheet in the
Tiller Console** — otherwise both sheets keep double-pulling the same feed
indefinitely, which wastes Tiller's sync quota and creates two diverging
"current" sources of truth.
