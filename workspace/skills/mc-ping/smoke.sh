#!/usr/bin/env bash
# mc-ping smoke test — runs weekly via tests/test-skill-smoke.sh.
#
# Verifies the skill's preconditions are still healthy. Read-only. No mutation.
# Distinct from tests/test-mc-ping.sh which is the full integration test
# (register + heartbeat round-trip, agent state-changing).
#
# Exits:
#   0 — MC reachable, auth header accepted, skill is still wired correctly
#   1 — env missing, MC unreachable, or auth rejected — skill is rotten

set -uo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Walk up to the openclawsetup root (template) OR the agent dir (installed).
ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"

# Source whichever env file is present. Template has .env.local; installed agent
# has env exported by OpenClaw already.
if [[ -f "$ROOT/.env.local" ]]; then
  set -a; source "$ROOT/.env.local"; set +a
fi

if [[ -z "${MC_URL:-}" ]]; then
  echo "smoke: MC_URL not set — mc-ping precondition missing" >&2
  exit 1
fi
if [[ -z "${MC_API_KEY:-}" || "${MC_API_KEY}" == "CHANGE_ME" ]]; then
  echo "smoke: MC_API_KEY missing or still CHANGE_ME" >&2
  exit 1
fi

# Reachability probe — health endpoint or any 401-from-anonymous endpoint works.
# We don't want a full register-and-heartbeat here; that's the integration test.
HTTP_CODE="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 5 \
  "$MC_URL/api/agents" -H "x-api-key: $MC_API_KEY" 2>/dev/null || echo "000")"

case "$HTTP_CODE" in
  200|204)
    exit 0
    ;;
  401|403)
    echo "smoke: MC reachable but auth rejected (HTTP $HTTP_CODE) — MC_API_KEY may have rotated" >&2
    exit 1
    ;;
  000)
    echo "smoke: MC unreachable at $MC_URL — service down or URL changed" >&2
    exit 1
    ;;
  *)
    echo "smoke: MC returned unexpected HTTP $HTTP_CODE — endpoint contract may have changed" >&2
    exit 1
    ;;
esac
