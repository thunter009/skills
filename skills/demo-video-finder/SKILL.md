---
name: demo-video-finder
description: Find short, single-topic, reputable how-to and demo videos for a list of items (exercises, techniques, steps, moves), with jump-to timestamps for long ones. Returns only real, verified YouTube watch URLs and never fabricates video IDs.
when-to-use:
- add a demo video for each of these / find youtube tutorials for these exercises or steps
- attaching reference clips to a checklist, plan, or program (pairs with todoist-program-builder)
- you need a verified YouTube link, not a hallucinated video ID
category: web
related-skills:
- search
- extract
- todoist-program-builder
---

# Demo Video Finder

Find a good reference clip for each item in a list (rehab exercises, cooking steps, tool techniques, dance moves, …). The bar: **short, single-topic, reputable, and real** — a 1-minute focused demo beats a timestamp into a 15-minute compilation, and a fabricated video ID is worse than useless.

## Hard rules
- **Never invent a video ID.** Only return a `https://www.youtube.com/watch?v=…` URL that actually appears in search results.
- **Prefer short, single-exercise/step clips** (ideally < 3 min). Long multi-topic protocol videos are a bad user experience for "show me this one thing."
- **Reputable sources.** For fitness/rehab: E3 Rehab, Bob & Brad, Physiotutors, Precision Movement, Squat University, Ask Doctor Jo, Sports Injury Physio, Rehab Science, Medbridge, Hinge Health. For other domains, prefer recognized channels / official sources over random uploads.

## Method
1. **Search** with the Tavily search script, scoped to YouTube (do NOT use built-in WebFetch/WebSearch):
   `~/.claude/skills/search/scripts/search.sh '{"query":"<item> exercise demo physical therapy", "max_results": 6, "include_domains":["youtube.com"]}'`
   Filter results to URLs containing `/watch`.
2. **Pick the best short, single-topic clip** from a reputable channel. Note its approx duration if findable.
3. **If only a long / multi-topic video exists**, read its description/chapters to find where THAT item is demonstrated:
   `~/.claude/skills/extract/scripts/extract.sh '{"urls":["<video url>"]}'`
   then append a deep-link `&t=<seconds>s` (e.g. a 3:30 mark → `&t=210s`). Only use a timestamp you actually found — don't guess.
4. **Fallback:** if no confirmed watch URL, return a YouTube *search* URL and mark it `(search)`:
   `https://www.youtube.com/results?search_query=<url-encoded query>`

## Output
One line per item, compact markdown:
`N. <item> — [Channel — short title (~M:SS)](URL)` — tag `(short clip)`, `(timestamped)`, or `(search)`.

## Delegation
Runs great as a subagent (mechanical, parallelizable). **Subagents can't invoke skills**, so when delegating, paste the two script paths above into the subagent prompt and the hard rules, and have it return the markdown list. Batch all items into one subagent rather than one call per item.
