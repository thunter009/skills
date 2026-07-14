---
name: google-sheets-via-browser
description: >-
  Drive, read, and edit Google Sheets through a logged-in browser (atrium
  browser pane or any CDP browser CLI) when there is no API or service-account
  access. Covers bulk reading via htmlview, tab-preserving structural edits,
  cross-spreadsheet tab copies through the Drive-picker iframe, and migrating
  or consolidating Tiller Money sheets. Use when asked to read/edit/consolidate
  a Google Sheet without API credentials, or to migrate a Tiller sheet.
category: web
related-skills:
- playwright-cli
- claude-in-chrome
- atrium
---

# Google Sheets via a logged-in browser

No API/service-account access → drive the real Sheets UI through a browser
pane (atrium browser pane, `claude-in-chrome`, or Playwright CLI/CDP). This
is slower and more fragile than the Sheets API — use it only when API access
genuinely isn't available. Field-tested on a 45k-row Tiller Money migration.

## Reading sheet data at scale (read-only)

- **Best bulk-read path**: navigate to
  `https://docs.google.com/spreadsheets/d/<ID>/htmlview` — renders every
  visible tab as plain HTML, cheap to parse, no editor chrome.
  - Tab switcher elements: `.switcherItem` / `.switcherItemActive`. Switch
    tabs by dispatching a `MouseEvent('click')` on the target `.switcherItem`
    (a plain DOM click via automation click helpers may not register).
  - Tab content loads into a same-origin iframe `#pageswitcher-content`.
    Read rows with `iframe.contentDocument.querySelectorAll('tr')`.
  - Row indexing: row 0 = spreadsheet column letters (A, B, C…), row 1 = the
    sheet's actual header row, data starts at row index 2.
  - Big tabs (17k+ rows) need a 10-15s sleep after switching tabs before the
    iframe content is fully populated — read too early and you get a partial
    or stale DOM.
  - **Hidden tabs do not appear in htmlview.** If a tab is missing from the
    switcher, check whether it's hidden in the editor (see below).
- **Tab inventory (including hidden tabs)**: use the full editor DOM, not
  htmlview. `.docs-sheet-tab` / `.docs-sheet-tab-name` lists every tab,
  `.docs-sheet-active-tab` marks the current one, and each tab's color swatch
  is the `background-color` inline style on `.docs-sheet-tab-color`.
- **gid discovery**: click a tab in the editor and read `location.hash`
  (`#gid=<N>`); the htmlview iframe's `src` also carries a `gid=` param.
  Useful for building direct deep links to a specific tab.
- **Dead ends — don't waste time re-discovering these**:
  - The gviz endpoint (`.../gviz/tq?tqx=out:json`) returns `ACCESS_DENIED`
    for private sheets even called from the authenticated page's own JS
    context — the request runs as an `authuser` mismatch, not as "you".
  - `/export?format=csv` fetched from the page also fails: it's a
    cross-origin redirect with no CORS headers, so even `Page.setBypassCSP`
    doesn't help. There is no XHR/fetch shortcut around the UI for a
    private sheet — htmlview or the editor DOM are the only reliable reads.

## Writing / structural surgery

**The cardinal rule**: report and formula tabs reference data tabs by
**identity**, not by name. Deleting a tab and creating a new one with the
same name permanently `#REF!`s every formula that pointed at the deleted
tab — the new tab is a different object even if it looks identical in the
UI. To replace a tab's data without breaking anything that points at it:
**clear the existing tab's contents, then paste the new data into it.**
Clear+paste preserves the tab's identity, so formulas keep resolving and —
critically for Tiller — the feed binding keeps appending new rows into that
tab afterward. Never delete-and-recreate a tab that anything else
references.

- **Navigation/selection**: the Name Box input (`#t-name-box`) accepts a
  cell (`A1`), a range (`CA2:CL233`), or a whole-column reference (`H:CA`).
  Fill it and press Enter to jump/select.
- **Keyboard input**: use CDP `Input.dispatchKeyEvent` with paired
  `keyDown`/`keyUp` events, not a synthetic `KeyboardEvent` dispatched via
  `eval()` — Sheets' key handlers require a trusted event and ignore
  synthetic ones. Modifier bitmask: Alt=1, Ctrl=2, Meta=4, Shift=8 (additive).
  Examples: Cmd+A = key `a`, modifiers 4. Paste-special-values (Cmd+Shift+V)
  = key `v`, modifiers 12. In atrium, use the browser pane's `press` action,
  which issues real CDP key events under the hood.
- **The values-flatten trap**: paste-special-values freezes whatever the
  source formulas evaluated to **at the destination's evaluation context**.
  If a pasted formula references a tab name that doesn't exist in the
  destination spreadsheet, it silently evaluates to that formula's
  `iferror` fallback — often `0` — with no visible error. This is a silent
  data-corruption trap, not a loud failure. To port computed numbers
  correctly: copy the **range** from the spreadsheet where the formulas
  already resolve correctly, and paste-special-values that resolved range
  into the target. Sheets' web clipboard survives navigation between
  documents in the same browser pane, so copy-in-source /
  navigate-to-destination / paste-values-in-destination works.
- **Cell notes for provenance**: select the cell, press Shift+F2, type the
  note text, press Escape. Useful for leaving a breadcrumb on cells you
  hand-ported, e.g. "static values as of 2026-06-01; formula pattern was
  `=SUMIF(...)`, source: <spreadsheet URL>".

## Cross-spreadsheet tab copies

- Right-click the source tab → **Copy to** → **Existing spreadsheet**. This
  opens a Drive picker that is an **IFRAME** — accessibility-tree snapshots
  and DOM `find`/query tools cannot see inside it, so you can't click by
  finding an element. Instead:
  1. Paste the destination spreadsheet's full URL into the picker's search
     box (exact URL match avoids accidentally picking a similarly-named
     backup copy).
  2. Take a fresh screenshot, then click the resulting tile and the blue
     "Insert"/"Select" button using **coordinate clicks** via CDP
     `Input.dispatchMouseEvent` (`mousePressed` then `mouseReleased` at the
     same coordinates), reading pixel coordinates off the screenshot each
     time — don't reuse coordinates across screenshots taken at different
     zoom/scroll states.
  3. On the success dialog, click "Done".
- The copied tab lands named "Copy of `<original name>`" in the destination.
- **Formulas inside a copied tab still reference tab names, not the tabs
  you actually copied.** After the copy, they re-bind to any same-named tab
  that already exists in the destination spreadsheet (which may be the
  wrong tab), and show `#REF!` wherever the tab they need wasn't copied
  over at all. Always re-check formula tabs after a cross-spreadsheet copy.

## Operational discipline

- **Always** `File → Make a copy` of the target spreadsheet before doing any
  structural surgery (menu id `docs-file-menu`). This is the only cheap
  undo you have — Sheets version history is not a substitute when you're
  about to clear/paste over a tab with a live feed binding.
- Screenshot-verify every step before moving to the next. Decode a
  base64-embedded screenshot with:
  `grep -o 'iVBOR[A-Za-z0-9+/=]*' | head -1 | base64 -d`.
- **"Transport error / browser was closed" from the CLI is often a FALSE
  failure** — the action frequently executed anyway before the transport
  dropped. Verify with a screenshot before retrying; blind retries risk
  double-executing a paste or a delete.
- Keep each shell/tool call short (well under 60s). Long sleep-chains
  inside a single call can trip agent watchdogs and get killed mid-action.
- **atrium `eval` quirk**: only single-expression chains are reliable;
  multi-statement scripts with `const` declarations can silently return
  `null`. For async work, kick off an IIFE that writes its result to a
  `window` variable, then poll that variable in a later, separate `eval`
  call.
- A lone `#REF!` in a single header cell is often just a blocked
  `=image("https://...")` logo fetch behind Sheets' "Allow access to
  external data" banner — cosmetic, not a real reference error. **Never
  click "Allow"/"Request access" on the user's behalf** — that's a
  permission decision for the human account owner.

## Tiller Money migration

See `references/tiller-migration.md` for the Tiller-specific playbook:
what a "new sheet" migration actually copies (and doesn't), the minimum
viable tab set to port for continuity, schema differences between Tiller
sheet generations, and the budget-history flatten-before-trim sequence.
