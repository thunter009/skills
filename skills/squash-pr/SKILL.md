---
name: squash-pr
description: Triage open PRs and squash-merge selected ones onto the integration branch.
when-to-use:
- squash PRs, land open PRs, triage PRs
- When clearing a PR queue
permissions:
- bash
- read
- write
category: release
---

# Squash PRs via GitHub Merge

Review all open PRs, present a summary for triage, and squash-merge the ones the user approves through GitHub's PR merge path.

Do **not** land by manually pushing commits and then closing PRs. A landed PR must show as merged, not merely closed.

## Arguments

Parse the user's message for:
- **Specific PR** (optional): PR number or URL. If provided, skip to Step 2 for just that PR.
- **Target branch** (optional): Default = current branch (`git branch --show-current`).
- **`--auto` / "autonomous"** (optional): non-interactive mode — never ask "which PRs?"; instead apply the Autonomous merge gate below and merge only PRs that clear it. Everything else is skipped with a stated reason.
- **`--dry-run`** (optional, implies `--auto`): evaluate the gate and print the would-merge/skip verdict table, but execute **zero** merges.

## Step 1: List open PRs

```bash
gh pr list --state open --json number,title,author,headRefName,baseRefName,createdAt,labels,isCrossRepository \
  --jq '.[] | {number, title, author: .author.login, head: .headRefName, base: .baseRefName, age: .createdAt, fork: .isCrossRepository, labels: [.labels[].name]}'
```

Present a table to the user:

| # | Title | Author | Base | Fork? | Age |
|---|-------|--------|------|-------|-----|

Group by category:
- **Dependabot/Renovate** — dependency bumps (safe to batch-land)
- **Feature/fix PRs** — need individual review
- **Stale** — open > 30 days, may need closing

Ask: "Which PRs to squash-merge into `<target>`? (all, numbers, or skip)"

In `--auto` mode do NOT ask — select PRs via the Autonomous merge gate below and continue.

## Autonomous merge gate (`--auto` mode only)

A PR may be auto-merged ONLY when **all** of the following hold. Anything that fails a
condition is skipped — and every skip must state its blocking reason. Never silently drop a PR.

1. **Base is the integration branch** (`dev`). PRs targeting `main`/`master`/any prod branch
   are a hard hold — auto mode never touches them.
2. **Not a hard-hold PR.** Two independent checks — **the label check is authoritative, prose
   sniffing is only a fallback for repos that have no hold labels.**

   **a. No hold LABEL.** Skip any PR carrying one of the repo's hold labels. Step 1 already
   fetches `labels`; actually read them:

   ```bash
   HOLD_LABELS="${HOLD_LABELS:-hold,do-not-merge,agent-hold,operator-hold,ci-hold}"
   # NB: pipe to real jq — `gh --jq` takes the filter only and rejects `--arg`
   # ("accepts at most 1 arg(s), received 4").
   gh pr view <N> --json labels | jq -r --arg h "$HOLD_LABELS" \
     '[.labels[].name] as $l
      | ($h | split(",")) | map(select(. as $x | $l | index($x))) | join(",")'
   # non-empty output ⇒ SKIP, and name the label as the blocking reason
   ```

   A hold label is a deliberate machine-or-human decision to keep a PR out of the queue.
   Labels differ only in **who may remove them** — that is never the merging loop's business
   either way. Common vocabulary: `hold` / `do-not-merge` are the human's; `agent-hold` belongs
   to a review sweep (agent-fixable HIGH finding); `operator-hold` belongs to that sweep when a
   HIGH needs a human decision; `ci-hold` belongs to a CI green-up loop. **Never write or remove
   any of them** — only refuse to merge past them.

   **Readiness labels, when the repo uses them.** If `gh label list` shows `ready-to-merge`
   as a repo label, they GATE this merge: skip unless the PR wears `ready-to-merge`; skip if
   it wears `needs-review`; skip if it wears neither. Never write or remove them. Mechanical
   checks below still run, so a stale `ready-to-merge` whose head has moved still fails the
   review-SHA check. If the repo does not have those labels, this clause is a no-op.

   Why (private managed repo, 2026-08-23): treating them as view-only let the drain merge PRs still
   labelled `needs-review` (#2147, #2149, #2153) the moment CI went green, before the review
   sweep could promote the label.

   **b. No hold PROSE, and not structurally ineligible.** Skip drafts; skip cross-repository
   fork PRs; skip release PRs (title `Release:`/`release:` or head `release/*`); skip any PR
   whose title or body contains "DO NOT MERGE" (any case) or names a review gate
   ("operator merges", "legal review", "awaiting sign-off", etc.).

   Prose alone is not sufficient where labels exist: a repo can label a PR `hold` without ever
   editing its title, and a gate that reads only the title merges straight past it.
3. **Mergeable and green**: `mergeable == "MERGEABLE"` and every required check in
   `statusCheckRollup` has concluded SUCCESS. A PENDING/QUEUED check ⇒ skip this tick —
   never wait-and-merge. A FAILURE/ERROR check ⇒ skip. Read
   `gh pr view N --json mergeable,mergeStateStatus,statusCheckRollup`; do not trust
   `gh pr checks` alone (known to report phantom states after pushes).
4. **CI actually ran.** Leg 3 asks whether anything failed, which is the wrong question when
   the answer is "nothing ran" — a PR with zero workflow runs has no failing checks and reads
   as green. Run the check — do not infer it from the rollup:

   ```bash
   ~/.claude/skills/squash-pr/scripts/ci-evidence.sh <N> --repo <owner/name> [--min N]
   #  exit 0 CI_RAN · 1 CI_ABSENT · 3 INDETERMINATE
   ```

   **Merge only on exit 0. Treat 3 exactly like 1**, for the same reason as leg 5.

   It reads the SAME `statusCheckRollup` snapshot leg 3 reads, and counts **distinct
   completed GitHub Actions workflow runs** (identified by an `/actions/runs/<id>/` details
   URL), ignoring `SKIPPED`/`CANCELLED`. Each choice is load-bearing:

   - **One snapshot, not two.** An earlier draft read the `actions/runs` API instead. Two
     sources meant two moments: a run could be queued and visible to `actions/runs` while
     still absent from the rollup, so leg 3 saw nothing pending, this leg saw a queued run,
     and both passed on a PR nothing had validated. One snapshot cannot disagree with itself.
   - **Completed only.** An in-flight run is evidence CI *is running*, not that it *ran*.
     Refusing costs one tick — the loop re-evaluates next cycle — and closes the race above.
   - **Distinct runs.** Three re-runs of one workflow are one workflow's worth of evidence;
     `--min` must not be satisfiable by retries of a single job.
   - **`--min 0` is a usage error**, not a permissive setting: it would make the comparison
     vacuously true and silently disable the whole leg.
   - **Actions only.** Third-party app checks are excluded because they are precisely the
     signal that made #1608 look green. **LIMITATION:** a repo whose CI is entirely
     non-Actions (CircleCI, Buildkite) always reports CI_ABSENT — do not enable this leg there.

   Why this leg exists: a private repo's PR #1608 merged on 2026-08-11 carrying exactly one check — a green
   CodeRabbit app check — and **no GitHub Actions check-suite at all**. Actions was healthy
   repo-wide (sibling PRs carried 14-15 checks each); the suite was simply never created for
   that SHA, and a rebase did not bring it back. It reached `main` and shipped in a release
   having been tested by nothing. Legs 3 and 4 fail in different directions; both are required.
5. **A real review exists at the current head, with no unresolved HIGH findings.**
   Run the check — do not eyeball it:

   ```bash
   ~/.claude/skills/squash-pr/scripts/review-evidence.sh <N> --repo <owner/name>
   #  exit 0 REVIEWED · 1 UNREVIEWED · 3 INDETERMINATE
   ```

   **Merge only on exit 0. Treat 3 exactly like 1** — no `gh`, an API error, or a malformed
   payload means the check failed, not that the PR passed, and a half-provisioned or offline
   machine is precisely when it is most likely to be wrong.

   What it asserts, and why prose was not enough: **CodeRabbit's green check is not proof of
   review** — it also goes green on "Review limit reached" (rate limit), on base-branch skips
   ("Auto reviews are disabled…"), and on free-plan-no-seat (walkthrough only). None of those
   leave a review body, so the check needs no signature list to reject them; it looks for
   positive evidence and finds none. It additionally rejects a substantive review left at an
   **older commit** — a review of code that is no longer the code being merged — plus PENDING
   (unsubmitted) reviews and sub-40-char rubber stamps.

   Review present but with HIGH-severity findings not visibly resolved/answered ⇒ skip
   ("unresolved HIGH finding"). That judgment stays human/agent-side; the script answers
   "did a review happen at this SHA", not "was it satisfied".

Merge strategy in auto mode is squash-only via `gh pr merge --squash` (Steps 3a-bis + 3b
unchanged — auto mode still carries/authors the customer note, since unattended merging is
exactly when a dropped note goes unnoticed) —
target repos enforce linear history. A landed PR must show as *merged*, never
closed-after-manual-push.

If `gh pr merge` fails in auto mode: leave the PR open, record the exact error as the skip
reason, and move on (no interactive skip/retry/abort prompt).

In `--dry-run`, stop after gate evaluation: print the verdict table
(| # | Title | Verdict | Reason |) and exit without merging.

## Step 2: Pre-flight

### 2a: Resolve target branch + detect checkout mode

```bash
git fetch --prune origin
TARGET=$(git branch --show-current)
```

If the user specified a different target branch, set `TARGET` to that name (don't `git checkout` yet — see the mode gate below). If the target doesn't exist locally or on origin, abort: "Branch `$TARGET` not found."

**Squash-merge is a GitHub server-side op — the local sync is incidental.** Skip every local branch-mutating step when the checkout is diverged or shared, otherwise the `--ff-only` pull fails (diverged) or a shared `HEAD` gets corrupted (sister sessions). Detect that up front:

```bash
REMOTE_ONLY=0
# (1) local target not fast-forwardable to origin (has commits origin lacks → ahead or diverged)
AHEAD=$(git rev-list --count "origin/$TARGET..$TARGET" 2>/dev/null || echo 0)
[ "${AHEAD:-0}" -gt 0 ] && REMOTE_ONLY=1
# (2) sister Claude sessions sharing this checkout (shared HEAD) — anchored cwd match, ancestor-excluded
ANCESTORS=" "; p=$$
while [ "$p" -gt 1 ]; do ANCESTORS="$ANCESTORS$p "; p=$(ps -o ppid= -p "$p" | tr -d ' '); done
SISTERS=$(ps -axo pid,command | grep -E "/\.local/bin/claude (--session-id|--resume) " | grep -v grep \
  | while read -r pid _; do
      case "$ANCESTORS" in *" $pid "*) continue;; esac
      lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep -qx "n$(pwd)" && echo x
    done | wc -l | tr -d ' ')
[ "${SISTERS:-0}" -gt 0 ] && REMOTE_ONLY=1
echo "TARGET=$TARGET ahead=$AHEAD sisters=$SISTERS REMOTE_ONLY=$REMOTE_ONLY"
```

If `REMOTE_ONLY=1`: do **not** run any local branch-mutating git op (no `git checkout`, stash, or `git pull`). Merges still go through GitHub and merge SHAs are read from `gh`. Tell the user: "Diverged/shared checkout — merging remote-only, leaving the local checkout untouched." `$TARGET` is used only to filter PRs by base branch (Step 3a).

When `REMOTE_ONLY=0` and the user specified a target other than the current branch, switch to it:
```bash
[ "$REMOTE_ONLY" = 0 ] && [ "$TARGET" != "$(git branch --show-current)" ] && git checkout "$TARGET"
```

### 2b: Protect local changes (clean checkout only)

**Skip this entire step when `REMOTE_ONLY=1`.** Check `git status --porcelain`. If dirty:
```bash
[ "$REMOTE_ONLY" = 0 ] && git stash push -u -m "squash-pr: stash before merge sync"
```

Do this **once** before processing any PRs. Do NOT pop until Step 4.

Then update the local target:

```bash
[ "$REMOTE_ONLY" = 0 ] && git pull --ff-only origin "$TARGET"
```

## Step 3: Merge each PR (sequential — complete one before starting the next)

For each selected PR, run 3a through 3c as a unit:

### 3a: Verify target and preview

Fetch PR metadata:

```bash
gh pr view "$PR" --json number,title,baseRefName,headRefName,mergeStateStatus,isDraft,commits
```

If `baseRefName != "$TARGET"`, skip and report: "PR #$PR targets `<base>`, not `<target>`."
If `isDraft == true`, skip and report: "PR #$PR is still draft."

Preview commits and diff:

```bash
gh pr view "$PR" --json commits --jq '.commits[].messageHeadline'
gh pr diff "$PR" --stat
```

Show commit count and headline summary.

### 3a-bis: Carry the customer note into the merge body

`--body ""` discards everything in the PR body. In repos that harvest opt-in
release-note footers from *commit* text, that silently drops the one thing the
author wrote for end users — the footer never reaches the commit, so the
release-time harvest finds nothing and the customer-facing changelog stays
frozen while user-visible work ships. (Observed in a private data-platform repo, 2026-08-07:
three releases of user-visible fixes, customer feed stuck five versions back.)

Build the merge body before merging:

```bash
# Footer lines the author wrote for end users. Passed via file, never
# interpolated into a shell string — PR bodies are untrusted author text.
gh pr view "$PR" --json body --jq '.body' > /tmp/pr-body.txt
MERGE_BODY="$(grep -iE '^[[:space:]]*customer-note:[[:space:]]*\S' /tmp/pr-body.txt || true)"
```

Drop any line whose text is still an unedited template placeholder (e.g.
containing `REPLACE ME`) — publishing that to customers is worse than
publishing nothing.

**If `MERGE_BODY` is empty**, check whether this repo uses the convention at
all: it does if any of `docs/ops/customer-release-notes.md`,
`scripts/lib/customer-notes.js`, or a `Customer-Note` mention in
`.github/PULL_REQUEST_TEMPLATE.md` exists. If it does *and* the PR's diff
touches a user-facing surface (in one private repo, `scripts/lib/customer-surfaces.js`
defines this; elsewhere use judgement — UI, public API, user-visible copy),
**write the note yourself from the diff**: one plain-English present-tense
sentence for a customer, no jargon, no scopes/PR numbers/issue IDs. You have
the diff in Step 3a; the author who forgot is not in the loop at merge time,
and this is the last moment the change can reach the feed.

Skip authoring for internal-only work — refactors, tests, CI, docs, pipelines,
admin-only screens. An empty body is the correct outcome there, and a filler
note is worse than none.

In `--dry-run`, print the `MERGE_BODY` you would use (or "none — internal") in
the verdict table rather than merging.

### 3b: Re-check the exact head, then squash-merge through GitHub

Capture the head immediately before the final gate and merge. In `--auto` mode, re-run every
Autonomous merge-gate leg against this snapshot; if the head differs from the head evaluated in
Step 1/2, start the gate over on the new head. Where readiness labels exist, require the final label
set to contain `ready-to-merge`, omit `needs-review`, and omit every hold label. Leave
`ready-to-merge` on the merged PR as an audit trail.

```bash
FINAL_HEAD="$(gh pr view "$PR" --json headRefOid --jq '.headRefOid')"
```

Use GitHub's PR merge operation:

```bash
gh pr merge "$PR" --squash --delete-branch --match-head-commit "$FINAL_HEAD" \
  --subject "<PR title> (#<PR number>)" --body "$MERGE_BODY"
```

`$MERGE_BODY` is empty for internal-only PRs, which reproduces the previous
`--body ""` behaviour exactly.

Do not use `gh pr close` to mark landed work as done.

**`gh pr merge` returning 0 does not mean the PR merged.** If the base branch
has a **merge queue** enabled, `--squash` *enqueues* the PR: it stays `OPEN`
(queued) while the queue re-runs the required checks, then lands it — or dequeues
it on failure. Never assume an immediate merge. Poll for the terminal state
(this is a no-op when no queue is active: the first poll already reads `MERGED`):

```bash
# Await the queued->merged transition. ~10 min budget: a merge queue re-runs the
# full required-check set per entry, so landing is not instant.
QSTATE=""; MERGE_SHA=""
for _ in $(seq 1 60); do
  IFS=$'\t' read -r QSTATE MERGE_SHA < <(
    gh pr view "$PR" --json state,mergeCommit --jq '[.state, (.mergeCommit.oid // "")] | @tsv')
  case "$QSTATE" in
    MERGED) break ;;          # landed (directly, or via the queue)
    CLOSED) break ;;          # dequeued/rejected without merging
    *) sleep 10 ;;            # OPEN == still queued -> keep polling
  esac
done
if [ "$REMOTE_ONLY" = 0 ]; then
  git fetch origin "$TARGET"
  git pull --ff-only origin "$TARGET"
fi
case "$QSTATE" in
  MERGED) LANDED["$PR"]="${MERGE_SHA:0:7}" ;;   # sourced from gh, works in remote-only mode
  CLOSED) FAILED["$PR"]="closed without merging (dequeued by the merge queue?)" ;;
  *)      PENDING["$PR"]="still queued after 10m — not merged; re-check next tick" ;;
esac
```

Only report a PR as **landed** when `state == MERGED`. A PR still `OPEN` after the
poll is **queued, not merged** — report it as pending, leave it alone, and
re-check on the next tick; never close it or claim it landed. A `CLOSED`
(un-merged) result means the queue dequeued it — treat as a merge-block (Step 3c).

### 3c: Merge-block handling

If `gh pr merge` fails:
1. Show the exact GitHub/CLI reason
2. Leave the PR open
3. Ask the user how to proceed: skip this PR, retry after fixing checks/conflicts, or abort batch
4. Do not close the PR manually

## Step 4: Restore and prune

No manual push or close step is needed; GitHub already merged the PR.

Prune deleted remote branches:

```bash
git fetch --prune origin
```

Restore stash if one was created (clean checkout only — `REMOTE_ONLY=1` never stashed):
```bash
[ "$REMOTE_ONLY" = 0 ] && git stash pop
```

If stash pop conflicts, warn the user (their local changes clash with landed PRs).

## Step 5: Summary

Print a results table (draw from the `LANDED` / `PENDING` / `FAILED` maps):

| # | Title | Status |
|---|-------|--------|
| 7 | bump pygments 2.19→2.20 | Merged (abc1234) |
| 9 | feat: add export flag | Queued (awaiting merge queue) |
| 12 | fix: typo in README | Skipped (blocked) |

List any PRs left open and why. A **Queued** PR (`PENDING`) is not a failure —
it entered the merge queue and will land on a later tick; report it as such
rather than merged or skipped.

## Error recovery

- Merge rejected by GitHub: leave PR open; report reason and ask skip/retry/abort
- Branch protection or merge queue required: do not bypass; use the repo-required path or ask
- `--delete-branch` fails: warn, don't block — the PR is merged
- Local `git pull --ff-only` fails after merge: fetch and report; do not rewrite local history. If it recurs, the checkout is likely diverged — re-run with `REMOTE_ONLY=1` (Step 2a) and skip the local sync entirely
- Stash pop conflicts: warn the user; their local changes clash with the merged PRs
- Diverged or sister-shared checkout (`REMOTE_ONLY=1`): never run `git checkout`/`stash`/`pull`; merge via `gh` and report SHAs from `gh pr view` only — the PRs still land server-side
