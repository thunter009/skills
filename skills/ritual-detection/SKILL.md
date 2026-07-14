---
name: ritual-detection
description: Mine CASS for repeated prompts that should become new skills.
when-to-use:
- ritual detection, repeated prompts, new skill candidates
- When searching for automation opportunities
user_invocable: true
allowed-tools: Bash(*)|Read|Write
category: meta
---

Run ritual detection across all CASS session history to find prompts repeated 5+ times. Each is a candidate for a new skill.

**Step 1 -- Extract frequent prompts:**
```bash
cass search "*" --robot --limit 1000 --fields minimal 2>/dev/null | python3 -c "
import sys, json
from collections import Counter
d = json.load(sys.stdin)
hits = d.get('hits', [])
# User prompts are typically in the first 3 lines of a session
prompts = [h.get('content', '')[:120].strip() for h in hits
           if h.get('line_number', 0) <= 3 and h.get('content', '').strip()]
counts = Counter(prompts)
print('=== Ritual Detection Report ===')
print()
rituals = [(p, c) for p, c in counts.most_common(50) if c >= 5]
emerging = [(p, c) for p, c in counts.most_common(50) if 3 <= c < 5]
print(f'Rituals (5+ occurrences): {len(rituals)}')
for p, c in rituals:
    print(f'  {c:3d}x  {p}')
print()
print(f'Emerging patterns (3-4 occurrences): {len(emerging)}')
for p, c in emerging:
    print(f'  {c:3d}x  {p}')
"
```

**Step 2 -- Classify each ritual:**

| Count | Status | Action |
|-------|--------|--------|
| 10+ | RITUAL | Extract into a skill immediately |
| 5-9 | Emerging | Worth investigating, may become a skill |
| 3-4 | Pattern | Monitor for growth |

**Step 3 -- For each ritual, recommend:**
- Skill name (kebab-case)
- What the skill would do
- Whether an existing skill already covers it (check installed skills)

Write the report to `.session-journal.md` so it persists.
