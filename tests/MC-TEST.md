# Mission Control integration test

Verifies the agent ↔ MC integration works end-to-end. Two layers:

1. **Plumbing** — `tests/test-mc-ping.sh`: standalone shell test, no agent involved. Confirms MC is reachable, auth is correct, contract works.
2. **Agent path** — `/mc-ping` skill via Telegram. Confirms the agent can use the same plumbing through its own tools.

If layer 1 passes but layer 2 fails, the bug is in the agent's tool invocation or env propagation — not in MC.

## Prerequisites

- `bootstrap.sh` has run successfully on the install machine.
- Mission Control is running on `$MC_URL` (default `http://localhost:3000`). Check with `lsof -i :3000`.
- `.env.local` has `MC_URL` and `MC_API_KEY` set (not `CHANGE_ME`).

## Layer 1 — standalone shell test

```bash
cd ~/cookclaw  # or wherever the install repo lives
./tests/test-mc-ping.sh
```

Expected output:

```
=== MC ping test ===
MC_URL:   http://localhost:3000
agent:    cookclaw-test

1. checking reachability...
   ok — MC reachable, auth accepted
2. registering agent...
   ok — agent id: 1
3. POSTing heartbeat...
   ok — heartbeat acknowledged
4. confirming agent visible in MC...
   ok — agent visible in dashboard

=== PASS ===
```

If step 1 fails with 401/403: `MC_API_KEY` mismatch. Check `~/.openclaw/mission-control/.env` for the actual key var name and value; ensure it matches `.env.local`.

If step 1 fails with connection refused: MC isn't running. Restart with `cd ~/.openclaw/mission-control && pnpm dev`.

If step 2 returns no `agent.id`: schema drift in MC. Inspect raw response (script prints it).

## Layer 2 — agent path via Telegram

Open MC dashboard at `$MC_URL` in a browser. Then DM the agent on Telegram:

```
/mc-ping
```

Expected reply (single line):

```
MC ✓ heartbeat sent — agent "<your-agent-name>" (id <N>). Dashboard: http://localhost:3000
```

In the MC dashboard, confirm:
- Agent appears in the agent list with the right name + framework=`openclaw`
- Last-seen timestamp is recent (within the past minute)

## Failure modes

| Symptom | Likely cause |
|---|---|
| Agent says "MC not configured" | `MC_API_KEY` is unset or `CHANGE_ME` in the daemon's env. Check `~/.openclaw/.env` symlink → `.env.local`. |
| Agent says "MC actions are owner-only" | Requesting Telegram user isn't on `commands.ownerAllowFrom`. Re-check `TELEGRAM_OWNER_ID` in `.env.local`. |
| Agent replies but no entry in dashboard | Skill ran but parsed wrong `agent.id`. Confirm `tests/test-mc-ping.sh` works first. |
| Agent says "step 1 failed: 401" | `MC_API_KEY` doesn't match MC's expected key. Edit `~/.openclaw/mission-control/.env` to match. |

## What this test does NOT cover

- Bidirectional task sync (MC → agent assignment) — needs the GET `/api/agents/{id}/heartbeat` polling loop, not yet wired.
- WebSocket / SSE push updates — not yet integrated.
- Cost / token tracking — agent doesn't yet emit token usage to MC.
- Skills Hub bidirectional sync.

These are roadmap items. Adding them follows the same pattern: layer 1 shell test first, then a skill that mirrors it.
