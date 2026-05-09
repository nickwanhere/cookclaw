#!/usr/bin/env bash
set -euo pipefail

# Deterministic rebuild of ~/.openclaw/openclaw.json from config/*.json fragments.
# Usage:
#   ./merge-configs.sh             # write
#   ./merge-configs.sh --dry-run   # print to stdout, don't write
#
# Secrets do NOT live in these files — JSON references env vars via SecretRef
# objects (e.g. { "fromEnv": "ANTHROPIC_API_KEY" }). Source .env.local before
# starting the openclaw gateway, not before this script.

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
TARGET="$OPENCLAW_HOME/openclaw.json"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
DRY_RUN=0

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

command -v jq >/dev/null 2>&1 || { echo "missing: jq (brew install jq)" >&2; exit 1; }

shopt -s nullglob
fragments=("$CONFIG_DIR"/*.json)
shopt -u nullglob

if [[ ${#fragments[@]} -eq 0 ]]; then
  echo "no config/*.json fragments found in $CONFIG_DIR" >&2
  exit 1
fi

# Strategy: deep-merge our fragments INTO existing ~/.openclaw/openclaw.json.
# - Onboard wrote provider-specific keys (models.providers.<x>.baseUrl, .models)
#   that we don't know how to compose. Preserving them.
# - Our fragments add/override only what we own (plugins, channels, agents.defaults).
# - Strip any key starting with `_` recursively (used for in-file `_comment` docs;
#   OpenClaw's schema rejects unrecognized keys).
merged="$({
  if [[ -f "$TARGET" ]]; then cat "$TARGET"; else echo '{}'; fi
  for f in "${fragments[@]}"; do cat "$f"; done
} | jq -s '
  reduce .[] as $c ({}; . * $c)
  | walk(if type == "object" then with_entries(select(.key | startswith("_") | not)) else . end)
')"

if [[ $DRY_RUN -eq 1 ]]; then
  printf '%s\n' "$merged"
  exit 0
fi

mkdir -p "$OPENCLAW_HOME"
if [[ -f "$TARGET" ]]; then
  cp "$TARGET" "$TARGET.bak.$(date +%Y%m%d-%H%M%S)"
fi
printf '%s\n' "$merged" > "$TARGET"
echo "wrote $TARGET"
echo "remember to source .env.local before starting the gateway."
echo
echo "SECURITY NOTE: 'openclaw doctor', 'update', 'configure' resolve env refs"
echo "to plaintext credentials in openclaw.json (issue #9627). After running"
echo "any of those, re-run this script to restore SecretRef placeholders."
