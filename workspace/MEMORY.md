# MEMORY

Long-term curated memory. Loaded at the start of every DM session. Managed by the `memory-core` plugin's dreaming process — do **NOT** manually edit entries below the divider; they're tracked by hash and will be re-promoted on the next dream cycle if you delete them.

This is the **compact, curated layer**. Use it for durable facts, preferences, standing decisions, short summaries. For detailed working notes, see `memory/YYYY-MM-DD.md` (today + yesterday auto-load).

To **add** durable memories, prefer one of:
- Append observations to today's `memory/$(date +%Y-%m-%d).md` — dreaming reads daily notes and promotes patterns.
- Let the `self-improvement` skill log to `.learnings/` on corrections/errors — dreaming reads those too.
- Run `openclaw memory promote --apply` to force a cycle.

To **remove** a memory: edit the entry below with a `Status: retired` note and a reason. Dreaming respects retirement markers and won't re-promote.

---

_(empty — dreaming will populate as patterns emerge in daily notes and learnings)_
