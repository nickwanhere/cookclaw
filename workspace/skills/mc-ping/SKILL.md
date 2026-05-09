---
name: mc-ping
description: Use when the user types `/mc-ping`, `/ping mc`, "send heartbeat to MC", or "ping mission control". Sends a heartbeat to the local Mission Control dashboard so the owner can confirm the agent ↔ MC integration is alive. Owner-only telemetry; never expose results to non-owner channel members.
allowed-tools: Bash(curl:*), Bash(jq:*), Read
---

# /mc-ping skill

Send a heartbeat to Mission Control. This is the smallest end-to-end test of the agent → MC path: register the agent, then trigger a heartbeat. If both succeed, the integration plumbing (URL, auth, contract) is verified.

## Preconditions

- `MC_URL` and `MC_API_KEY` are exported in the daemon environment (sourced from `~/.openclaw/.env` which symlinks to the install repo's `.env.local`).
- The requesting user is the owner (per `commands.ownerAllowFrom` and USER.md owner row).
- Mission Control is running on `$MC_URL` (default `http://localhost:3000`).

If any precondition fails, reply with the specific failure (e.g. `MC not configured — MC_API_KEY is unset or CHANGE_ME`) and stop. Do not improvise endpoints or fabricate success.

## Agent name

Use the value of `agent_name` from `~/.openclaw/workspace/IDENTITY.md` (rendered at install time). Fall back to `cookclaw` if IDENTITY.md is missing. The MC agent name must match `^[a-zA-Z0-9][a-zA-Z0-9._-]{0,62}$` — lowercase + hyphens are safe.

## Steps

1. **Register** (idempotent — MC returns 200 if the agent already exists, 201 if new; both responses include `agent.id`):

   ```bash
   curl -fsS -X POST "$MC_URL/api/agents/register" \
     -H "x-api-key: $MC_API_KEY" \
     -H "Content-Type: application/json" \
     -d "{\"name\":\"$AGENT_NAME\",\"role\":\"agent\",\"framework\":\"openclaw\"}"
   ```

   Parse `.agent.id` from the response with `jq -r '.agent.id'`. If empty or non-numeric, reply with the raw response and stop.

2. **Heartbeat**:

   ```bash
   curl -fsS -X POST "$MC_URL/api/agents/$AGENT_ID/heartbeat" \
     -H "x-api-key: $MC_API_KEY"
   ```

   Success if response has `.status == "HEARTBEAT_OK"` OR `.success == true` (MC's openapi.json and actual implementation disagree on shape — accept either). The full success response also includes `agent`, `checked_at`, and may include `message: "No work items found"` when there are no pending tasks. Treat that as healthy, not as an error.

3. **Reply** to the user. Single line under 200 chars:

   `MC ✓ heartbeat sent — agent "<name>" (id <id>). Dashboard: <MC_URL>`

   On any failure, reply with the failed step + status code + first 200 chars of response body. No invented details.

## Owner-only enforcement

- Refuse if the requesting Telegram user is not on `commands.ownerAllowFrom`. Reply: `MC actions are owner-only.`
- Never include `MC_API_KEY` in any reply, log, or memory note. The audit log MUST redact it.
- Per `AGENTS.md` "Mission Control integration" section, MC is operator-side telemetry — invisible to topic members.

## Audit

After a successful or failed run, write a one-line entry to today's audit log:

`HH:MM | mc-ping | <owner-id> | <result> | agent_id=<id>`

Use the same logging mechanism as other skills (per AGENTS.md skill workshop rules). Do NOT include the API key.

## Notes

- This skill is the agent-side mirror of `tests/test-mc-ping.sh` (which runs standalone without an agent). If the shell test passes but this skill fails, the bug is in the agent's tool invocation or env propagation, not in MC.
- For the design of the MC integration (auth model, what's visible to whom), see `AGENTS.md` § "Mission Control integration".
- We deliberately do NOT add an automatic heartbeat tick yet — first verify manual triggering works, then decide whether to bind it to the existing 10-minute heartbeat cadence.
