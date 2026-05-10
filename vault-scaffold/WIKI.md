# Wiki

This vault is the durable knowledge layer for an OpenClaw agent. Markdown files written here are readable in Obsidian and queryable by the agent via the memory-wiki plugin.

## Layout

| Folder | Holds |
|---|---|
| `entities/` | One page per durable thing — people, projects, systems, organizations |
| `concepts/` | Ideas, patterns, techniques, policies |
| `syntheses/` | Compiled rollups, summaries, cross-cutting reviews |
| `sources/` | Imported raw material, bridge-backed pages |
| `reports/` | Generated dashboards |
| `Logs/` | Daily audit log: `Logs/<YYYY-MM-DD>.md`, one line per consequential agent action |

## Operations

The agent uses three verbs:

- **INGEST** — turn raw material into a wiki page (writes via `wiki_apply` or direct filesystem when freeform).
- **QUERY** — answer questions by consulting the wiki first; cite sources via page id or relative path.
- **LINT** — surface stale, contradictory, or under-evidenced pages via `wiki_lint`.

See `AGENTS.md` in the agent workspace (`~/.openclaw/workspace/`) for the full operational protocol.

## Page conventions

Entity pages use frontmatter ids of the form `entity.<canonical-id>`. Example:

```yaml
---
pageType: entity
entityType: person
id: entity.ricky-wong
aliases:
  - Ricky
  - rwong
privacyTier: local-private
---

Notes about Ricky go here. Anything outside the managed-section markers (when added by `wiki_apply`) is preserved across compile cycles.
```

The agent expands this convention on first ingest; you don't need to author pages by hand to bootstrap. Manual edits in Obsidian are respected and re-indexed.

## Owner edits

This vault is yours. Edit in Obsidian freely. The agent treats your edits as authoritative — if your edit and an agent claim conflict, your edit wins on next compile (unless evidence in a `claims:` block says otherwise).
