#!/usr/bin/env bash
set -euo pipefail

# Live integration test: MC reachability + auth + heartbeat round-trip.
# Standalone — no agent involved. Run AFTER bootstrap.sh while MC is on :3000.
#
# Verifies:
#   1. MC_URL is reachable
#   2. MC_API_KEY is accepted (x-api-key header)
#   3. POST /api/agents/register returns an agent id
#   4. POST /api/agents/{id}/heartbeat returns success
#
# This catches the "plumbing exists but auth/contract is wrong" failure mode
# before adding agent-side complexity. If this passes but the agent skill
# doesn't show entries in MC, the bug is in the skill, not in MC.
#
# Usage:
#   ./tests/test-mc-ping.sh                # default agent name "cookclaw-test"
#   ./tests/test-mc-ping.sh my-agent-name  # custom name

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_LOCAL="$SCRIPT_DIR/.env.local"
[[ -f "$ENV_LOCAL" ]] || { echo "error: $ENV_LOCAL not found — run from repo root" >&2; exit 1; }
set -a; source "$ENV_LOCAL"; set +a

: "${MC_URL:?MC_URL not set in .env.local}"
: "${MC_API_KEY:?MC_API_KEY not set in .env.local}"
[[ "$MC_API_KEY" == "CHANGE_ME" ]] && { echo "error: MC_API_KEY is still CHANGE_ME" >&2; exit 1; }

AGENT_NAME="${1:-cookclaw-test}"

echo "=== MC ping test ==="
echo "MC_URL:   $MC_URL"
echo "agent:    $AGENT_NAME"
echo

# 1. reachability + auth — try /api/status first (cheap GET with auth)
echo "1. checking reachability..."
status_code=$(curl -s -o /tmp/mc-status -w "%{http_code}" \
  -H "x-api-key: $MC_API_KEY" "$MC_URL/api/status" || echo "000")
case "$status_code" in
  200) echo "   ok — MC reachable, auth accepted" ;;
  401|403) echo "   FAIL — auth rejected (status $status_code). MC_API_KEY in .env.local doesn't match MC's expected key." >&2
           echo "   Check $HOME/.openclaw/mission-control/.env for the actual key var." >&2; exit 1 ;;
  000) echo "   FAIL — could not connect to $MC_URL. Is MC running? lsof -i :3000" >&2; exit 1 ;;
  *) echo "   FAIL — unexpected status $status_code" >&2; cat /tmp/mc-status >&2; exit 1 ;;
esac

# 2. register agent (idempotent — 200 if exists, 201 if new; both return id)
echo "2. registering agent..."
register_resp=$(curl -fsS -X POST "$MC_URL/api/agents/register" \
  -H "x-api-key: $MC_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$AGENT_NAME\",\"role\":\"agent\",\"framework\":\"openclaw\"}")

agent_id=$(echo "$register_resp" | jq -r '.agent.id // empty')
if [[ ! "$agent_id" =~ ^[0-9]+$ ]]; then
  echo "   FAIL — could not extract agent.id from response:" >&2
  echo "$register_resp" >&2
  exit 1
fi
echo "   ok — agent id: $agent_id"

# 3. trigger heartbeat
echo "3. POSTing heartbeat..."
hb_resp=$(curl -fsS -X POST "$MC_URL/api/agents/$agent_id/heartbeat" \
  -H "x-api-key: $MC_API_KEY")
hb_success=$(echo "$hb_resp" | jq -r '.success // false')
if [[ "$hb_success" != "true" ]]; then
  echo "   FAIL — heartbeat did not return success=true. Response:" >&2
  echo "$hb_resp" >&2
  exit 1
fi
echo "   ok — heartbeat acknowledged"

# 4. check that MC remembers the agent (round-trip via GET /api/agents)
echo "4. confirming agent visible in MC..."
agents_resp=$(curl -fsS -H "x-api-key: $MC_API_KEY" "$MC_URL/api/agents")
found=$(echo "$agents_resp" | jq -r --arg name "$AGENT_NAME" '.agents[]? | select(.name == $name) | .id // empty' | head -1)
if [[ "$found" != "$agent_id" ]]; then
  echo "   FAIL — agent '$AGENT_NAME' (id=$agent_id) not found in GET /api/agents response" >&2
  exit 1
fi
echo "   ok — agent visible in dashboard"

echo
echo "=== PASS ==="
echo "MC integration verified end-to-end. Open $MC_URL to see '$AGENT_NAME'."
