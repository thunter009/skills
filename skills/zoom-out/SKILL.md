---
name: zoom-out
description: Zoom out one abstraction layer and map the relevant modules and callers.
when-to-use:
- zoom out, give me the bigger picture, how does this fit together
- When unfamiliar with a section of code and needing a map before diving in
permissions:
- read
category: code
---

# Zoom Out

The user doesn't know this area of code well. Go up a layer of abstraction. Give them a map of all the relevant modules and callers — what each one is responsible for, who calls it, and where the data flows.

If the repo keeps a domain glossary (`CONTEXT.md`), use its vocabulary for the map. Reference everything as `file_path:line_number` so the map is clickable.

Do not make changes. Do not descend back into implementation detail until the user picks a spot on the map.
