---
name: work
description: Use when the user types `/work`, `/queue`, `/done`, or `/blocked`, or asks "what are you working on" / "what's pending" / "what's blocked" in chat. Returns a tight summary of agent work state — TaskFlow tasks, recent sub-agent spawns from the OpenClaw ledger, today's audit log entries. Distinct from built-in `/status` which shows gateway/model/token diagnostics; this skill shows what work the agent is actually doing.
allowed-tools: Bash(taskflow:*), Bash(openclaw tasks:*), Read
---

# /work skill

Reply with a tight summary of agent work state across three sources:

1. **Owner-curated tasks** — `taskflow list --json` for current TaskFlow state. Group by section: In Progress, Pending Validation, Blocked, Backlog (top 3). Skip Done unless `/done` was the trigger.
2. **Sub-agent / spawn activity** — `openclaw tasks list --since 1h --json` for recent ledger activity. Show last 5 entries with status (success / failure / running) and short summary.
3. **Today's audit log** — Read `~/.openclaw/wiki/main/Logs/$(date +%Y-%m-%d).md` if it exists. Show the last 5 actions.

## Output shape

Aim under 1500 chars (Telegram message budget). Format:

```
🟢 Agent up — Xh Xm
Active: N tasks
  • [P1] task title (status hint)
  • [P2] task title (status hint)
Pending validation: N
Blocked: N — top reason: "..."
Recent activity (last hour): N spawns, M completed, K failed
Last 3 actions: ...
```

If everything is empty: `Agent idle. No tasks active, no recent activity.`

## Triggers

- `/work` → full summary (what's the agent working on)
- `/queue` → tasks only (skip activity + log)
- `/done [today|week]` → completed section, scoped
- `/blocked` → only blocked tasks with reasons
- "what are you working on" / "what's pending" → same as `/work` but conversational tone

## Naming note

OpenClaw has a built-in `/status` command that shows gateway/model/token diagnostics. This skill is named `/work` to avoid collision and to better reflect what it shows: agent **work state**, not framework state. Use built-in `/status` for "is the gateway healthy?" and `/work` for "what is the agent doing?"

## Constraints

- Read-only. This skill never mutates state.
- If `taskflow` or `openclaw tasks` shells out with non-zero exit, surface the error briefly — don't fabricate state.
- Do not reveal task contents from tasks the requester does not have authority to see (per USER.md trust list). Filter `notify` field if necessary.
