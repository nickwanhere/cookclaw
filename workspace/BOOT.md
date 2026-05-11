# BOOT

Runs once at gateway startup via the bundled `boot-md` hook. Execute these steps in order, then reply with the silent-reply token (no visible output).

## 1. Register with Mission Control

Mission Control needs to know this agent exists so the owner sees it in the dashboard. Registration is idempotent (200 if already registered, 201 if new) — safe to run on every boot.

```bash
AGENT_NAME=$(jq -r '.agents.list[0].id // "main"' ~/.openclaw/openclaw.json 2>/dev/null)
[[ -z "$AGENT_NAME" || "$AGENT_NAME" == "null" ]] && AGENT_NAME="cookclaw"

curl -fsS -X POST "${MC_URL:-http://localhost:3000}/api/agents/register" \
  -H "x-api-key: $MC_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$AGENT_NAME\",\"role\":\"agent\",\"framework\":\"openclaw\"}" \
  > /dev/null
```

If `$MC_API_KEY` is unset or empty, skip this step silently — MC integration isn't configured.

## 2. Heartbeat once

Just to mark "I'm alive" so the dashboard's last-seen timestamp updates immediately on restart (instead of waiting for the next heartbeat tick).

```bash
if [[ -n "${MC_API_KEY:-}" ]]; then
  AGENT_ID=$(curl -fsS -X POST "${MC_URL:-http://localhost:3000}/api/agents/register" \
    -H "x-api-key: $MC_API_KEY" -H "Content-Type: application/json" \
    -d "{\"name\":\"$AGENT_NAME\",\"role\":\"agent\",\"framework\":\"openclaw\"}" \
    | jq -r '.agent.id')
  if [[ "$AGENT_ID" =~ ^[0-9]+$ ]]; then
    curl -fsS -X POST "${MC_URL:-http://localhost:3000}/api/agents/$AGENT_ID/heartbeat" \
      -H "x-api-key: $MC_API_KEY" > /dev/null
  fi
fi
```

## 3. Verify vault layout exists

Ensure the 5 memory-wiki folders + Logs/ exist in the vault. Bootstrap already does this, but a daemon restart on a vault that's been moved/cleaned should self-heal.

```bash
VAULT="${VAULT_PATH:-$HOME/.openclaw/wiki/main}"
for d in entities concepts syntheses sources reports Logs; do
  [[ -d "$VAULT/$d" ]] || mkdir -p "$VAULT/$d"
done
```

## 4. Done

Reply with only the silent-reply token. The boot check should be invisible to topic members and any active conversations.

## Notes

- BOOT.md is for **mechanical setup**, not reasoning. Don't add "check email" or "review yesterday's tasks" here — those belong in HEARTBEAT.md.
- Failures are non-fatal. If MC is unreachable or the vault dir is read-only, log briefly and continue. The agent should still come up.
- The `boot-md` hook spawns an actual agent turn for this file, so token cost applies — but only once per gateway restart, which is rare.
