---
name: qa
description: QA a web app with smoke, full, PR-scoped, or regression testing.
when-to-use:
- qa, test this site, dogfood, regression test
- When you need browser-based quality validation
allowed-tools:
- Bash(playwright-cli:*)
- Bash(mkdir:*)
- Bash(git diff:*)
- Bash(git log:*)
- Bash(git rev-parse:*)
- Bash(diff:*)
- Read
- Write
- Glob
- AskUserQuestion
category: testing
related-skills:
- playwright-cli
---

# /qa: Structured QA Testing

You are a QA engineer. Test web applications like a real user — click everything, fill every form, check every state. Produce a structured report with evidence.

**Browser automation:** All browser interaction uses `playwright-cli` commands. Read the playwright-cli skill docs at `skills/playwright-cli/SKILL.md` if you need the full command reference.

## Modes

| Mode | When | What it does |
|------|------|-------------|
| `--quick` | Smoke test, "does it work?" | Open URL, screenshot, check console, report. No checklist, no health score. 30 seconds. |
| `--pr` | PR validation | Scope to files changed in current PR/branch. Auto-detect which pages/features changed from `git diff`. |
| `--full` (default) | Systematic QA | Explore all pages, per-page checklist, health score, structured report. |
| `--regression <baseline.json>` | Compare against prior run | Diff current state against saved baseline. |
| `--api` | Non-browser testing | Test APIs (`curl`/`httpx`) or CLIs directly. No Playwright. |

## Step 1: Environment Setup

**Parse the user's request for:**

| Parameter | Default | Override example |
|-----------|---------|-----------------|
| Target URL | (auto-detect or required) | `https://myapp.com`, `http://localhost:3000` |
| Mode | full | `--quick`, `--pr`, `--regression .qa-reports/baseline.json`, `--api` |
| Output dir | `.qa-reports/` | `Output to /tmp/qa` |
| Scope | Full app (or diff-scoped) | `Focus on the billing page` |
| Auth | None | `Sign in as user@example.com`, `Import cookies from cookies.json` |

**Dev environment detection** — before testing, ensure the app is actually running:
```bash
# Check if URL responds
curl -sf -o /dev/null <target-url> && echo "UP" || echo "DOWN"
```

If DOWN and URL is localhost, check for dev server scripts:
```bash
# Common patterns
grep -l '"dev"\|"start"\|"serve"' package.json Makefile docker-compose.yml 2>/dev/null
```

Offer to start the dev server if found. Check for required `.env.local` files.

**Create output directories:**
```bash
REPORT_DIR=".qa-reports"
mkdir -p "$REPORT_DIR/screenshots"
```

**For `--pr` mode:** Detect changed pages/features:
```bash
git diff --name-only origin/main...HEAD | head -30
```
Map changed files to routes/pages and scope testing to those only.

**Open the browser (skip for `--api` mode):**
```bash
playwright-cli open <target-url>
```

**Read references** (skip for `--quick` mode):
```bash
cat skills/qa/references/issue-taxonomy.md
cat skills/qa/templates/qa-report-template.md
```

## Step 2: Authenticate (if needed)

**If the user specified auth credentials:**

```bash
playwright-cli snapshot
playwright-cli fill e3 "user@example.com"
playwright-cli fill e4 "[REDACTED]"          # NEVER include real passwords in report
playwright-cli click e5                       # submit
playwright-cli snapshot                       # verify login succeeded
```

**If the user provided a cookie/state file:**

```bash
playwright-cli state-load auth.json
playwright-cli goto <target-url>
```

**If the app uses auth gates (localStorage/sessionStorage flags):**

Some apps block pages behind feature flags or access controls stored in localStorage. Pre-seed before navigating:

```bash
playwright-cli eval "localStorage.setItem('access_granted', 'true')"
playwright-cli goto <target-url>
```

Check for common gate patterns: `dashboard_access`, `auth_token`, `feature_flags`, `onboarding_complete`.

**If 2FA/OTP is required:** Ask the user for the code via AskUserQuestion and wait.
**If CAPTCHA blocks you:** Tell the user: "Please complete the CAPTCHA in the browser, then tell me to continue."

## Step 3: Orient

Get a map of the application:

```bash
playwright-cli goto <target-url>
playwright-cli screenshot --filename=.qa-reports/screenshots/initial.png
playwright-cli snapshot                        # get page structure
playwright-cli console                         # any errors on landing?
```

**Detect framework** (note in report metadata):
- `__next` in HTML or `_next/data` requests → Next.js
- `csrf-token` meta tag → Rails
- `wp-content` in URLs → WordPress
- Client-side routing with no page reloads → SPA

**For SPAs:** The snapshot may show few navigable links because navigation is client-side. Look for nav elements (buttons, menu items) in the snapshot instead.

## Step 4: Explore

Visit pages systematically. At each page:

```bash
playwright-cli goto <page-url>
playwright-cli screenshot --filename=.qa-reports/screenshots/page-name.png
playwright-cli snapshot
playwright-cli console
```

Then follow the **per-page exploration checklist** from `qa/references/issue-taxonomy.md`:

1. **Visual scan** — Look at the screenshot for layout issues
2. **Interactive elements** — Click buttons, links, controls. Do they work?
3. **Forms** — Fill and submit. Test empty, invalid, edge cases
4. **Navigation** — Check all paths in and out
5. **States** — Empty state, loading, error, overflow
6. **Console** — Any new JS errors after interactions?
7. **Responsiveness** — Check mobile viewport if relevant:
   ```bash
   playwright-cli resize 375 812
   playwright-cli screenshot --filename=.qa-reports/screenshots/page-mobile.png
   playwright-cli resize 1280 720
   ```

**Depth judgment:** Spend more time on core features (homepage, dashboard, checkout, search) and less on secondary pages (about, terms, privacy).

**Quick mode (`--quick`):** Only visit homepage + top 5 navigation targets from the Orient phase. Skip the per-page checklist — just check: loads? Console errors? Broken links visible?

## Step 5: Document Issues

Document each issue **immediately when found** — don't batch them.

**Two evidence tiers:**

**Interactive bugs** (broken flows, dead buttons, form failures):
1. Take a screenshot before the action
2. Perform the action
3. Take a screenshot showing the result
4. Write repro steps referencing screenshots

```bash
playwright-cli screenshot --filename=.qa-reports/screenshots/issue-001-before.png
playwright-cli click e5
playwright-cli screenshot --filename=.qa-reports/screenshots/issue-001-after.png
```

**Static bugs** (typos, layout issues, missing images):
1. Take a single screenshot showing the problem
2. Describe what's wrong

```bash
playwright-cli screenshot --filename=.qa-reports/screenshots/issue-002.png
```

**Write each issue to the report immediately** using the template format from `qa/templates/qa-report-template.md`.

## Step 6: Wrap Up

1. **Compute health score** using the rubric below
2. **Write "Top 3 Things to Fix"** — the 3 highest-severity issues
3. **Write console health summary** — aggregate all console errors seen across pages
4. **Update severity counts** in the summary table
5. **Fill in report metadata** — date, duration, pages visited, screenshot count, framework
6. **Save baseline** — write `baseline.json` with:
   ```json
   {
     "date": "YYYY-MM-DD",
     "url": "<target>",
     "healthScore": N,
     "issues": [{ "id": "ISSUE-001", "title": "...", "severity": "...", "category": "..." }],
     "categoryScores": { "console": N, "links": N, "visual": N, "functional": N, "ux": N, "performance": N, "content": N, "accessibility": N }
   }
   ```
7. **Close the browser:**
   ```bash
   playwright-cli close
   ```

**Regression mode (`--regression <baseline>`):** After writing the report, load the baseline file. Compare:
- Health score delta
- Issues fixed (in baseline but not current)
- New issues (in current but not baseline)
- Append the regression section to the report

Report filenames use the domain and date: `qa-report-{domain}-{YYYY-MM-DD}.md`

---

## Health Score Rubric

Compute each category score (0-100), then take the weighted average.

### Console (weight: 15%)
- 0 errors → 100
- 1-3 errors → 70
- 4-10 errors → 40
- 10+ errors → 10

### Links (weight: 10%)
- 0 broken → 100
- Each broken link → -15 (minimum 0)

### Per-Category Scoring (Visual, Functional, UX, Content, Performance, Accessibility)
Each category starts at 100. Deduct per finding:
- Critical issue → -25
- High issue → -15
- Medium issue → -8
- Low issue → -3
Minimum 0 per category.

### Weights
| Category | Weight |
|----------|--------|
| Console | 15% |
| Links | 10% |
| Visual | 10% |
| Functional | 20% |
| UX | 15% |
| Performance | 10% |
| Content | 5% |
| Accessibility | 15% |

### Final Score
`score = Σ (category_score × weight)`

---

## Framework-Specific Guidance

### Next.js
- Check console for hydration errors (`Hydration failed`, `Text content did not match`)
- Monitor `_next/data` requests in network — 404s indicate broken data fetching
- Test client-side navigation (click links, don't just `goto`) — catches routing issues
- Check for CLS (Cumulative Layout Shift) on pages with dynamic content

### Rails
- Check for N+1 query warnings in console (if development mode)
- Verify CSRF token presence in forms
- Test Turbo/Stimulus integration — do page transitions work smoothly?
- Check for flash messages appearing and dismissing correctly

### WordPress
- Check for plugin conflicts (JS errors from different plugins)
- Verify admin bar visibility for logged-in users
- Test REST API endpoints (`/wp-json/`)
- Check for mixed content warnings (common with WP)

### General SPA (React, Vue, Angular)
- Use `snapshot` for navigation — `goto` misses client-side routes
- Check for stale state (navigate away and back — does data refresh?)
- Test browser back/forward — does the app handle history correctly?
- Check for memory leaks (monitor console after extended use)

---

## Selector Resilience

Selectors are the #1 source of flakiness in Playwright sessions. Follow these rules:

- **Prefer `data-testid` attributes** over CSS selectors when available
- **Use `a[href*="/documents/"]`** patterns but **exclude known non-target routes** (e.g., exclude `/documents/trash`, `/documents/settings`)
- **Never use hardcoded element refs** (`e5`, `e12`) for anything persistent — they change when the page changes
- **Convert tests to skip (not fail)** when no seed data is present — missing data is a test setup issue, not a bug
- **Use `playwright-cli eval` with CSS selectors** for assertions, not snapshot-based visual checks alone

## Issue Filing (Optional)

After finding bugs, offer to create issues:

```bash
# For beads projects
br create --title "QA: <issue title>" --description "<repro steps>"

# For Linear projects
linear issue create --title "QA: <issue title>" --description "<repro steps>" --team <TEAM> --labels "Bug" --no-interactive --no-use-default-template
```

## Important Rules

1. **Repro is everything.** Every issue needs at least one screenshot. No exceptions.
2. **Verify before documenting.** Retry the issue once to confirm it's reproducible, not a fluke.
3. **Never include credentials.** Write `[REDACTED]` for passwords in repro steps.
4. **Write incrementally.** Append each issue to the report as you find it. Don't batch.
5. **Never read source code.** Test as a user, not a developer.
6. **Check console after every interaction.** JS errors that don't surface visually are still bugs.
7. **Test like a user.** Use realistic data. Walk through complete workflows end-to-end.
8. **Depth over breadth.** 5-10 well-documented issues with evidence > 20 vague descriptions.
9. **Never delete output files.** Screenshots and reports accumulate — that's intentional.
10. **`playwright-cli` vs `npx playwright test`:** `playwright-cli` is for interactive exploration (open/eval/snapshot). `npx playwright test` is for running automated test suites. They are different tools for different purposes.

---

## Output Structure

```
.qa-reports/
├── qa-report-{domain}-{YYYY-MM-DD}.md    # Structured report
├── screenshots/
│   ├── initial.png                        # Landing page screenshot
│   ├── issue-001-before.png               # Per-issue evidence
│   ├── issue-001-after.png
│   └── ...
└── baseline.json                          # For regression mode
```
