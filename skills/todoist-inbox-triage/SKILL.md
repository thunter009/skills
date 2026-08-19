---
name: todoist-inbox-triage
description: Triage the Todoist inbox into projects, groups, and deletes.
when-to-use:
- todoist inbox, clean todoist inbox, organize tasks
- When the inbox is messy
category: pm
related-skills:
- todoist
- todoist-kickoff-prompt
---

# Todoist Inbox Triage

Workflow for reviewing and organizing a cluttered Todoist inbox into the right projects.

## Prerequisites

- `td` CLI installed and authenticated (see `todoist` skill)
- Tavily extract available at `~/.claude/skills/extract/scripts/extract.sh`
- `bird` CLI for tweet extraction (optional, falls back to title inference)
- `social-fetch` skill for non-X social URLs — LinkedIn, Instagram, TikTok, Reddit, HN, Bluesky, Mastodon, Threads (optional)

## Workflow

### 1. Pull inbox and existing projects

```bash
td inbox
td project list
```

Note existing projects — you'll map inbox items to them in step 4.

### 2. Fetch full descriptions

**CRITICAL:** `td inbox` only shows titles. Descriptions contain URLs, context, and action items that are invisible in the list view. Fetch them before categorizing:

```bash
# For each task ID from td inbox:
td task view id:TASK_ID
```

Batch this — don't skip it. Items that look like "no context" bookmarks often have full action items in descriptions. Skipping this step has led to near-deletion of important items.

### 3. Categorize

With titles AND descriptions in hand, group into categories:

| Category | Signal |
|----------|--------|
| **Actionable tasks** | No URL, describes work to do |
| **GitHub repos** | `github.com` URL |
| **Articles** | Blog/docs URL (not social media) |
| **Tweets/social** | `x.com`/`twitter.com`, LinkedIn, Instagram, TikTok, Reddit, HN, Bluesky, Mastodon, or Threads post URL |
| **Other bookmarks** | Any other URL |

### 4. Extract content for context

Batch extract URLs to understand what each item is about:

```bash
~/.claude/skills/extract/scripts/extract.sh '{"urls":["url1","url2",...]}'
```

**Limits:** max 20 URLs per call. Split into batches if needed.

**For tweets:** Tavily fails ~100% on x.com URLs. Use `bird` CLI instead:

```bash
# CORRECT — read a tweet by ID (extract numeric ID from URL after /status/)
bird read <tweet-id> --plain

# DANGER — `bird tweet` POSTS a new tweet! Never use it to read.
```

Batch tweet reads: `for id in ID1 ID2 ...; do bird read "$id" --plain; done`

If `bird` is not available, fall back to inferring topic from the tweet author name and visible title text.

**For other social platforms** (LinkedIn, Instagram, TikTok, Reddit, HN, Bluesky, Mastodon, Threads): Tavily also fails on most of these. Invoke the `social-fetch` skill if installed — it returns normalized author/text/engagement JSON via a free-first strategy chain (public APIs → browser → Wayback). If `social-fetch` is not installed, fall back to inferring topic from the URL slug, author handle, and visible title text — same as the no-`bird` tweet fallback.

### 5. Present categorized summary

For each category, show a table with:
- Item name/description
- Extracted summary (1 line)
- Any useful metadata (stars for repos, author for tweets)

### 6. Triage each category

Go category by category, asking the user what to do. Common actions:

| Action | When |
|--------|------|
| **Complete** | Task is already done |
| **Delete** | Bookmark-style item better stored elsewhere (GitHub stars, Instapaper, etc.) |
| **Move to project** | Item belongs in an existing project |
| **Keep in inbox** | User will handle manually soon |

**Important:** The inbox is an "act on this" queue, not a bookmark dump. Items were added for a reason — understand that reason before suggesting deletion.

### 7. Batch move/delete

**Verify IDs before executing** — use `td task view` to confirm you have the right task, especially in batch operations.

```bash
# Move to project (no confirmation needed)
td task move TASK_ID --project "Project Name"

# Delete (requires --yes flag)
td task delete TASK_ID --yes

# Complete (NOT close/done — those commands don't exist)
td task complete TASK_ID
```

Chain operations with `&&`:

```bash
td task move ID1 --project "Foo" && td task move ID2 --project "Foo"
```

**Note:** `#ProjectName` in quick add fails silently for multi-word project names. Always use `td task move --project "Name"` instead.

### 8. Verify clean inbox

```bash
td inbox
```

Report summary: how many items completed, deleted, moved (by destination), and remaining.

### 9. Offer kickoff prompts (post-triage handoff)

After the summary, surface `todoist-kickoff-prompt` for any items moved to projects that look ready to start now (cold-start refs in description + dated within 7 days). The triage routed the work; the kickoff prompt is the on-ramp back into a session.

Skip this step if all moved items were trivial one-clicks or bare titles — there's nothing to anchor a prompt on.

Ask one question:
> N items just moved into projects look ready to kickoff (description has refs + acceptance + soon-due). Want self-contained prompts generated? Auto-suggest: <list>.

If yes, hand the candidate list to `todoist-kickoff-prompt`.

## Guidance for categorization

- **Bookmarks are not tasks.** Repos, tweets, and articles saved to inbox are reference material. Suggest deleting from Todoist and using purpose-built tools (GitHub stars, Instapaper, read-later apps) unless user has a "Reading List" or "Bookmarks / Read Later" project.
- **Group by purpose, not format.** A tweet about AI agents and a blog post about AI agents go to the same project.
- **Check existing projects first.** Map items to existing projects before suggesting new ones.
- **Batch similar items.** Don't ask about each of 30 tweets individually — group them and ask about the group.
