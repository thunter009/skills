---
name: knowledge-graph-capture
description: Before archiving consumed or reference content (videos, articles, bookmarks, finished tasks), distill its durable knowledge into applied, wikilinked evergreen notes in your Obsidian knowledge graph — tied to your actual situation, not generic summaries.
when-to-use:
- "capture this into my knowledge graph / second brain / garden"
- "incorporate the knowledge before we archive / close these"
- Before closing educational or reference items during tracker triage (pairs with `todoist-project-triage`)
- After research/reading where the concept will recur and is worth keeping
- Distinct from Claude Code auto-memory (agent working-notes) — this seeds the human's evergreen note graph
category: docs
related-skills:
- todoist-project-triage
---

# Knowledge Graph Capture

When you're about to **archive, close, or delete** something that carries durable knowledge — a "watch later" video, a bookmarked article, a research thread, a rich task — capture the *substance* into the knowledge graph **first**, so the learning survives the bookmark.

The output is not a generic summary. It is an **applied evergreen note**: the concept distilled, the rule stated, and — the load-bearing part — **how it applies to this specific person's situation**, cross-linked into their existing notes.

## Memory vs. knowledge graph — don't confuse them

| | Claude Code auto-memory (`~/.claude/projects/<slug>/memory/`) | Knowledge graph (Obsidian vault) |
|---|---|---|
| Audience | Future *agents* | The *human's* second brain |
| Content | Working state, decisions, project facts | Evergreen domain concepts, applied |
| Lifespan | Until superseded | Long-lived, compounding |
| This skill writes here? | No | **Yes** |

`todoist-project-triage` step 5 already extracts task *substance* to agent-memory. This skill is the complementary move for *conceptual / reference* knowledge that belongs in the human's note graph. A tax-strategy video isn't agent working-state — it's an evergreen concept.

## 1. Find the vault and its evergreen convention

Don't hardcode a path — detect it:

```bash
# Common vault roots; adapt to what exists
ls -d ~/obsidian/*/ ~/*vault*/ ~/mnt/*vault*/ 2>/dev/null
```

Most PARA+Garden vaults keep evergreen notes in **`03_Garden/`** (or `Garden/`, `Evergreen/`, `notes/`). Match the **existing** house style before inventing one:
- Frontmatter or none? (grep a few existing notes for `^---`)
- `[[wikilinks]]` vs tags? (most Obsidian vaults: wikilinks by basename, folder-independent)
- A `Last updated:` line? A `Source:` line?

If the evergreen area is empty (no convention yet), use a simple, durable shape: `# Title` → `Last updated: YYYY-MM-DD` → `Source:` → sections → `## See also` wikilinks.

## 2. Triage what's worth capturing

Capture concepts that are **durable and likely to recur**. Skip trivia and one-offs.

- **Capture:** domain concepts (a tax rule, an architecture pattern, a legal test), frameworks, decision rules, anything the person will reason with again.
- **Skip / just archive:** pure entertainment, hyper-specific one-time facts, content already fully covered by an existing note, items that aren't actually knowledge ("Eradicate Debt Fast" motivational clip in a tax list → not a tax concept).
- **Watch for the buried action:** some "reference" items are actually a *dated action* in disguise (a viral "IRS owes you a refund, file by July 10" post). Those don't get a concept note — they get **verified and upgraded into a task**, not archived. See `todoist-project-triage` premise-verification.

## 3. Write the applied note

Each note, ~half a screen:

1. **Concept** — the idea in plain terms.
2. **The rule / thresholds** — the precise mechanics (cite the statute/section/spec where it matters).
3. **How it applies to ME** — the load-bearing section. Tie it to the person's actual entities, projects, properties, codebase. This is what makes it worth more than the source video.
4. **`[[wikilinks]]`** — into their existing notes AND between these concept notes, so it joins the graph instead of orphaning.
5. **Source** — the original URL, so nothing from the source is lost and they can still consume it.

**Verify factual claims before writing them.** Evergreen notes get trusted and re-read — an error compounds. For tax/legal/medical/financial or any precise-fact domain, web-verify the specifics (rates, thresholds, whether a law/program exists) rather than asserting from memory. A wrong threshold in a note the person relies on later is worse than no note.

If you create 3+ related notes, add a small **MOC (map-of-content)** note linking them by theme — turns orphans into a navigable cluster.

## 4. THEN archive

Only after the knowledge is captured and the wikilinks resolve, close/archive the source item. If you're mid-triage, leave a one-line pointer on the closed task (or in its comment) to where the knowledge landed.

**Sequencing matters:** capture → verify → link → *then* archive. Archiving first risks the knowledge evaporating if the capture step is skipped or interrupted.

## Multi-agent safety

Writing into the vault is a mutating op. If other sessions may share the vault checkout:
- Detect sister sessions (see `todoist-project-triage` multi-agent section).
- Prefer the evergreen area (`03_Garden`) when other agents are working elsewhere in the vault — it's usually uncontested.
- Register file reservations (agent-mail) on your target glob; release when done.
- If the vault is a synced mount (not git), there's no commit — notes persist directly and the Obsidian indexer wires the graph on next open. Confirm with `git rev-parse` before assuming a commit step exists.

## Anti-patterns

- **Generic transcript dump.** A summary of "what the video said" with no "how it applies to me" is low-value — that's what the source already is.
- **Dangling wikilinks.** Verify link targets resolve (basename search across the vault) before finishing. A `[[note]]` to a non-existent file is fine only if you mean to write it next; otherwise it's a broken edge.
- **Capturing trivia.** Not every bookmark earns an evergreen note. If it won't recur, just archive it.
- **Asserting unverified facts.** Precise-domain claims (rates, thresholds, law existence) get verified, not recalled.
- **Archiving before capturing.** The whole point is the knowledge outlives the bookmark — do it in that order.

## Verification

After capture, before archiving:
- [ ] Every note has a concrete "applies to me" section (not just the generic concept)
- [ ] All `[[wikilinks]]` resolve (or are intentional forward-links)
- [ ] Precise-domain facts were verified, not recalled
- [ ] Source URL preserved in each note
- [ ] MOC added if 3+ related notes
- [ ] Source items archived only *after* the above
