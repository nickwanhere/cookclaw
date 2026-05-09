---
chat_id: REPLACE_WITH_TELEGRAM_CHAT_ID
thread_id: REPLACE_WITH_TELEGRAM_THREAD_ID
name: human-readable topic name
created: 2026-05-09
---

# Topic context

This file is the per-topic context for one Telegram conversation. The agent loads it (via sync-topics.sh) when sessions start in this topic. Edit freely — this is meant to be a living document.

## Members

- Owner (you)
- (collaborator name) — scope: (which projects / topics they can authorize)
- (external contact name) — communication only on owner instruction

## Purpose

What this topic is for. One or two sentences. Keep it specific so the agent's context is shaped right.

## Conventions for this topic

- Tone: (terse-technical / formal / casual / etc.)
- Format preferences: (code-first / prose / bullet-heavy)
- What to skip: (pleasantries, background context the members already share)

## Active tasks

References to TaskFlow IDs. Updated as work progresses.

- (task:project-NNN) — short title — section/status

## Recent decisions

Rolling buffer of last 10 decisions made in this topic. Append new at top, prune old.

- 2026-05-09: Decided X over Y because Z

## Vault refs

Links to durable knowledge in the shared vault that's specifically relevant to this topic.

- [[Codebases/project-name]]
- [[Areas/Clients/client-name]]
