---
name: mealie
description: Read and write recipes in self-hosted Mealie via its REST API without corrupting them.
when-to-use:
- mealie, recipe, import recipe, add recipe to mealie, recipe manager
- Editing ingredients, units, or foods in a Mealie library
- Importing a recipe from a URL
category: home
---

# Mealie

Self-hosted recipe manager. Everything here is the REST API — never touch the Postgres
DB directly, and never drive the UI.

## Auth

One Touch ID per script. The Bitwarden **Desktop app must be running AND unlocked** —
its biometric IPC only serves the key while the app itself is unlocked. On repeated
`Message timed out waiting for Desktop app response`, stop retrying: `bwbio` falls back
to a master-password prompt, which needs a TTY and will hang an agent Bash call until it
times out. Hand the user a script to run instead.

```bash
export BW_SESSION=$(bwbio unlock --raw)          # tell the user a Touch ID prompt is coming
PASS=$(bw get password "Mealie" --raw 2>/dev/null)
TOKEN=$(curl -sf -X POST "$BASE/api/auth/token" \
  --data-urlencode "username=$EMAIL" --data-urlencode "password=$PASS" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')
unset PASS; bw lock >/dev/null 2>&1
```

## Endpoints

| Need | Call |
|------|------|
| Import from URL | `POST /api/recipes/create/url` `{"url": ..., "includeTags": true}` → returns slug |
| Read | `GET /api/recipes/{slug}` |
| Write | `PUT /api/recipes/{slug}` — **full-object replace** |
| List | `GET /api/recipes?page=N&perPage=100` (paginate on `total_pages`) |
| Foods / Units | `GET|POST /api/foods`, `/api/units`; `DELETE /api/foods/{id}` |
| Parse ingredients | `POST /api/parser/ingredients` — **see the warning below** |

## The four traps

These are the whole reason this skill exists. Each one has silently corrupted a real library.

**1. `display` is server-derived. You cannot set it.**
Mealie recomputes `display` from `quantity` + `unit` + `food` + `note` on every PUT; a
`display` you send is ignored. It also pluralizes the food name when quantity ≠ 1, so
food `pepper` renders as "peppers". The only way to control what the page reads is to get
the structured fields right.

**2. PUT is a full replace, not a patch.**
Always `GET` → mutate the object → `PUT` the whole thing back. Constructing a fresh
payload silently wipes every field you didn't mention.

**3. The built-in NLP parser is lossy and CORRUPTS. Do not trust it unreviewed.**
`POST /api/parser/ingredients` does not merely fail to link — it drops food names and
rewrites amounts, and because `display` is derived (trap 1), the wrong text *overwrites*
the real text. Observed in production:

- `1 (15-ounce) can chickpeas, rinsed` → `1 can or 15 ounce rinsed` — chickpeas gone
- `1/3 cup plus 2 tablespoons olive oil` → `¹/₃ cup (2 tablespoons)` — a different amount
- `1/2 cup butter` → `quantity=1` with `/2 cup butter` swallowed into an auto-created
  **food entity**, leaving the amount 2× too high and the foods table full of junk

If a library was bulk-imported through this parser, audit before trusting it. A coverage
metric ("83% of rows have a linked food") measures whether rows got linked, **not whether
they got linked to something true**.

Hand-mapping is the reliable path: source wording verbatim, prep modifiers in `note`,
`quantity`/`unit`/`food` set deliberately.

**The safest write mode is free-text `note` only — use it whenever you can.**
A URL import lands with **every row unstructured**: `quantity=0`, `unit=null`, `food=null`,
the whole line in `note`, and `display` just mirroring `note`. In that state you can rewrite
`note` freely — convert units, simplify names, split "salt and pepper" into two rows,
annotate with grams — and `display` renders exactly what you wrote. This bypasses traps 1,
3, and 4 entirely: no derived pluralization, no parser, no food/unit entities. Only reach
for structured `quantity`/`unit`/`food` when the recipe genuinely needs machine-readable
scaling or a shopping-list mapping; for human-readable edits, editing `note` is both safer
and simpler. (Splitting a row = append a new ingredient object with a fresh `referenceId`;
reuse existing `referenceId`s on rows you keep, or you break any `ingredientReferences` in
the steps.)

**4. Foods and units are entities, referenced by ID.**
`{"id": null, "name": "..."}` is rejected on PUT. Look up the real record (or `POST` to
create it) and embed that object. Beware: an ingredient's *text* can end up living inside
a junk food's `name` — **deleting that food destroys the text.** Rescue text into `note`
and unlink the food *before* deleting the entity.

**5. You cannot identify a junk food by its shape. Do not try.**
Cleaning up parser wreckage means deciding which food records are garbage. Every shape
heuristic tried against a real 155-recipe library produced false positives:

| Rule | What it destroyed |
|------|-------------------|
| name is `>4 words` | 147 **real** foods (`bone-in leg of lamb, 5 to 6 pounds`, `Better Than Bouillon beef base`) |
| name `starts with a digit` | `2% milk`, `80/20 ground beef` — ordinary grocery names |
| ASCII class `[/+%\-\d]` | *missed* en-dash junk (`–5 cloves garlic`) — and the same ASCII bug in the **verification** regex reported "0 junk foods" as a false all-clear |

Real product names are messy; a regex that decides what is "real" will keep finding false
positives. So:

- Junk = **leading punctuation only**, and test it unicode-aware (`not name[0].isalnum()`),
  never an ASCII character class.
- **Digit-leading names are ambiguous** (`2% milk` is real; `15-ounce can cannellini beans`
  is a swallowed line). Print them for a human; never auto-delete.
- Ground ambiguous rows against the **original source**, not against a pattern.
- **Dry-run every bulk delete and read the list.** The `>4 words` rule was caught this way;
  the digit rule was not, because it was applied.

The same trap applies to *quantities*. "Fix ranges to the low end" sounds mechanical, but
`1 3-4 pound organic chicken` is ONE chicken weighing 3–4 lb (low-end → three chickens) and
`2 1 second Cooking Sprays` is TWO one-second sprays. Both already match their source.

## Back up before writing

There is no undo. Snapshot every recipe + the foods table to a timestamped dir before any
bulk write, and say where the snapshot is:

```python
for slug in slugs:
    json.dump(api("GET", f"/api/recipes/{slug}"), open(f"{BK}/recipes/{slug}.json", "w"), indent=1)
```

Restore = PUT each file back to `/api/recipes/{slug}`.

## Importing from a URL

`POST /api/recipes/create/url` uses schema.org JSON-LD. When ingredients come back blank
but the title, image, and instructions are fine, the site is emitting a **Text-subtype
wrapper** instead of plain strings:

```json
{"@type": "PronounceableText", "textValue": "2 tablespoons red wine vinegar"}
```

Mealie's `clean_ingredients` falls through to its dict branch and writes empty rows.
Instacart does this on every recipe. Check the source before believing an import:

```bash
curl -s "$URL" | python3 -c "
import re,sys,json
m=re.findall(r'<script[^>]*ld\+json[^>]*>(.*?)</script>', sys.stdin.read(), re.S)
d=json.loads(m[0]); g=d.get('@graph', [d])
for i in g:
    if 'Recipe' in str(i.get('@type')): print(json.dumps(i.get('recipeIngredient')[:2], indent=1))"
```

If wrapped, extract `textValue` yourself and PUT the rows.

**Before extracting by hand, look for the upstream original.** Aggregator links (Instacart
especially) usually wrap a real recipe site and carry it in the URL — a `?referer=` param,
a canonical link, or the user can point you at it. Importing *that* URL (e.g. the NYT Cooking
page an Instacart link came from) yields clean schema.org rows with zero repair work. Try the
source before doing surgery on the aggregator's wrapped payload.

## Verify, always

`display` is derived and PUTs fail quietly. After every write, `GET` the recipe back and
print the rendered rows. A fix that "looks applied" often isn't — matching on a *displayed*
name ("peppers") when the stored food is `pepper` is a real failure mode.

## Read the steps before editing them

Trap 5's lesson — a shape/keyword heuristic cannot identify the right target — applies to
`recipeInstructions`, not just foods. Picking a step by keyword (`"salmon" + "cook"`) and
appending method-dependent guidance corrupted a real recipe: the note said "sear skin-side
down" on a step that actually **steams** the fish under a lid, so the instruction
contradicted itself. Before writing anything method-dependent (a technique note, a timing
tweak, adding/reordering steps), `GET` and read the full `recipeInstructions` text and
confirm what each step actually does. Never let a regex choose which step to edit, and never
assume a recipe's method from its title — read it.
