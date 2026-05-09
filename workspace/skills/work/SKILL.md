---
name: status
description: Use when the user types `/status`, `/queue`, `/done`, or asks "what's going on" / "what are you doing" / "what's pending" in chat. Returns a tight summary of current task state, recent agent activity, and blockers.
allowed-tools: Bash(taskflow:*), Bash(openclaw tasks:*), Read
---

# /status skill

Reply with a tight summary of agent state across three sources:

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

- `/status` → full summary above
- `/queue` → tasks only (skip activity + log)
- `/done [today|week]` → completed section, scoped
- `/blocked` → only blocked tasks with reasons
- "what's pending" / "what are you working on" → same as `/status` but conversational tone

## Constraints

- Read-only. This skill never mutates state.
- If `taskflow` or `openclaw tasks` shells out with non-zero exit, surface the error briefly — don't fabricate state.
- Do not reveal task contents from tasks the requester does not have authority to see (per USER.md trust list). Filter `notify` field if necessary.
