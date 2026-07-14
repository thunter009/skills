---
name: docs-organize
description: Reorganize loose files already in a folder into its subfolder taxonomy, with hash-based dedup, dry-run preview, and collision-safe moves. Domain-agnostic.
when-to-use:
- reorganize a folder, sort loose files into subfolders in place
- clean up these folders, file the loose docs, organize a directory
- after downloads-triage routes items into a folder and they need sorting within it
category: pm
related-skills:
- downloads-triage
---

# Organize a Folder (in place)

Sort the loose files in an existing folder into its subfolder taxonomy. Domain-agnostic — works on any
records, project, or document folder. The sibling `downloads-triage` skill routes *new* items from
Downloads/inboxes into destinations; **this skill reorganizes files already inside a folder** — sorting
loose root files into subfolders, relocating strays, sub-organizing, and de-duplicating.

The placement judgment (which file → which subfolder) is per-folder. The reusable, load-bearing part is
the **safety harness**: hash-based dedup, dry-run preview, collision-safe execution, and `~/.Trash`
instead of `rm`. Use `scripts/safe-reorg.py` for those.

## Pick or derive a taxonomy

If the folder already has subfolders, sort into them. Otherwise derive a scheme from what's actually in
the folder — by document type, by year, by project, by counterparty — and confirm it with the user
before moving anything. Match existing capitalization; don't rename established directories.

**Example — a real-estate property folder** (one shape among many; don't force it elsewhere):

| Subfolder | Holds |
|---|---|
| `Purchase/` | acquisition: contract, deeds, closing disclosure, appraisal, title, wires, loan docs, inspections |
| `Renovation/` | capital improvements: proposals/contracts, change orders, invoices, design, furnishings, `photos/` |
| `Operations/` | **one-off / event-driven**: repairs, landscaping, maintenance, mgmt agreements, insurance *quotes*, correspondence/drafts, payment *receipts* |
| `Compliance/` | regulatory: permits, affidavits, excise/hotel/sales tax, registrations, licenses, insurance declarations |
| `Statements/` | **recurring** statements/bills — mortgage servicer, utilities (electric/gas/water/TV/internet), bank/CC — one subfolder per provider (+ escrow analyses) |
| `Tax/` | tax-prep artifacts: logs, cross-refs, worksheets |

**Recurring vs one-off is the sharpest sorting axis.** Anything on an ongoing billing/account cycle —
statements, bills, periodic invoices from a servicer / utility / vendor — groups by *source* under a
`Statements/` (or `Bills/`) folder, one subfolder per provider. One-off, event-driven items file by
*type/event*. Don't scatter one provider's monthly bills across event folders, and don't pool unrelated
one-offs into `Statements/`.

## Safety rules (load-bearing — do not skip)

1. **Hash before you trash.** A same-named file in two places is NOT proof of a duplicate. `md5` both;
   trash the loose copy **only on an exact match**. Same name + different hash = a real variant
   (revision, signed-vs-draft, filed-vs-blank) → **leave it and flag**, never trash.
2. **`mv` to `~/.Trash`, never `rm`.** Trash is recoverable; `rm` is not.
3. **Dry-run first, always.** Build the move manifest, run the harness with `DRY=1`, confirm
   `missing=0` (every source path resolved → no filename typos), show the user, *then* `DRY=0`.
4. **Collision-safe on execute.** If a destination file already exists: identical hash → trash the
   source; different hash → skip and flag (never overwrite).
5. **Don't rename established directories** or touch already-sorted files without explicit OK — that's
   churn and breaks any references (e.g. links in an index/dashboard file).
6. **Leave ambiguous / undated / differing files in place and flag them** rather than guessing.
7. **Strays that belong elsewhere** (a doc for a different entity/project/property) → relocate to the
   right home or an archive folder, don't sort them into the wrong folder's subfolders.
8. **Classify bills/statements by issuer, not filename.** Recurring statements are routinely mis-named —
   `Invoice <GUID>.pdf`, a bare account number (`…114700094363.pdf`), `scan001.pdf`. Open and read the
   header: a utility/servicer issuer (`PPL Electric`, `Heller's Gas`) means a recurring statement →
   `Statements/<provider>/`, even when the filename says "Invoice". A name-only sort silently strands these.

## Workflow

1. **Scope + inventory.** `find <folder> -type f ! -name .DS_Store` for each target folder. Separate
   loose root files (the work) from already-foldered files (mostly leave alone).
2. **Pick/derive the taxonomy** (above). If the user asked for a "refined" scheme, present it and the
   per-file mapping for approval before moving anything.
3. **Hash-check suspected dups.** For any same-name-in-two-places or `* copy.pdf` / generic-name files,
   `md5 -q` both and record which are exact dups vs distinct variants.
4. **Identify generically-named files.** `ViewFile.pdf`, `Quote letter.pdf`, `scan001.pdf` — read page 1
   to classify before placing; don't guess from the name.
5. **Build the manifest** (`MOVE` / `TRASH` lines — format below) and run the harness `DRY=1`. Confirm
   `missing=0`. Show the plan.
6. **Execute** `DRY=0` after approval. Then **verify**: the root should hold only subfolders + any
   root-level index/dashboard files + intentionally-flagged files; report per-subfolder counts.

## Harness: `scripts/safe-reorg.py`

Reads a tab-separated manifest and applies it safely. Use a Python manifest (not raw shell `mv`) so
spaces / `&` / `()` in filenames are handled as data, not shell-quoted.

```
# manifest.tsv — one action per line, TAB-separated, absolute paths
MOVE<TAB>/abs/src.pdf<TAB>/abs/destdir            # keep filename
MOVE<TAB>/abs/src.pdf<TAB>/abs/destdir<TAB>new-name.pdf   # move + rename
TRASH<TAB>/abs/dup.pdf<TAB>exact md5 dup of <dest>       # reason required
```

```bash
DRY=1 python3 scripts/safe-reorg.py manifest.tsv   # preview — confirm missing=0
DRY=0 python3 scripts/safe-reorg.py manifest.tsv   # apply (mkdir -p dest, collision-safe, ~/.Trash)
```

The harness prints every action, refuses to overwrite (identical→trash source, different→skip+flag),
creates destination dirs, sends trashes to `~/.Trash`, and reports `moves / trashes / missing / applied`.

## Anti-patterns

- **Trashing a same-named file without hashing it.** Real variants (signed vs draft, filed vs blank)
  get destroyed. Hash first; flag mismatches.
- **`rm` instead of `mv ~/.Trash`.** No recovery.
- **Skipping the dry-run** because "it's just a few files." The dry-run is what catches a filename typo
  before it silently no-ops or mis-moves.
- **Forcing one folder's taxonomy onto a different kind of folder.** Derive per folder from contents.
- **Filing a mis-named recurring bill as a one-off invoice.** `Invoice <GUID>.pdf` from a utility is a
  statement → `Statements/<provider>/`; classify by issuer, or a name-sort leaves it in the wrong folder.
- **Renaming established subdirectories** for cosmetic consistency — breaks references, high churn, low value.
- **Over-reorganizing already-sorted files.** Touch the loose files and the strays; leave the rest.
