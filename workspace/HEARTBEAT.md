# HEARTBEAT

Recurring main-session checks. Fired by the OpenClaw heartbeat (default ~30 min). Each line is one check; the agent walks them in order, batches results, and acts on anything that needs attention. Empty heartbeats skip cheaply.

Tasks listed here are time-tolerant — missing one beat is fine. For hard deadlines (deal-breakers, payment windows, time-sensitive sends) use `cron` not heartbeat.

## tasks

- [ ] **Inbox sweep** — Telegram unread count. If non-zero, read summaries; if any need owner attention, surface in next reply.
- [ ] **Calendar peek** — events in next 4h. Surface conflicts, missing prep, or schedule risks.
- [ ] **Task drift check** — `taskflow list --status in_progress`. Anything in_progress > 4h with no recent activity is stuck. Move to `Blocked` with a `blockedReason:` describing why, or surface to owner.
- [ ] **Failed spawns** — `openclaw tasks list --status failure --since 30m`. If any, summarize the failure and either retry once or surface to owner.
- [ ] **MC heartbeat** — invoke the `mc-ping` skill so Mission Control's dashboard reflects this agent as alive. Idempotent: re-registers if needed, then POSTs heartbeat. Skip silently if MC is unreachable (offline, port closed) — do NOT surface MC outages to the owner unless they persist > 1h.

## daily — runs once at 09:00 local (cron, not heartbeat)

- Regenerate `~/.openclaw/wiki/main/Action Tracker.md` from `taskflow list --json`. Group by status, sorted by priority then due date.
- Archive yesterday's `Logs/<YYYY-MM-DD>.md` — append to month rollup, ensure it's in vault.
- Sweep `tasks/Done/` for items > 30 days old; offer owner an archive.

## not in heartbeat — explicitly out of scope

Anything with a hard deadline ("submit before 5pm Friday or deal dies") goes in `cron`, not here. Heartbeat misses beats; cron doesn't.
Anything that fires before every reply (memory recall, context retrieval) lives in the active-memory plugin, not here.
