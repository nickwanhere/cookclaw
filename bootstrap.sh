#!/usr/bin/env bash
set -euo pipefail

# Two-step OpenClaw template bootstrap.
#
# Prerequisite: cp .env.example .env.local && edit it with TELEGRAM_BOT_TOKEN,
# TELEGRAM_OWNER_ID, and your provider's API key (e.g. ANTHROPIC_API_KEY).
#
# Then: ./bootstrap.sh
#
# This orchestrates the full install:
#   1. setup-openclaw.sh — installs OpenClaw + TaskFlow + Mission Control
#   2. openclaw onboard --non-interactive — daemon + workspace + initial config (env-ref secrets)
#   3. onboard-agent.sh --non-interactive — renders IDENTITY/USER, generates provider config
#   4. sync-topics.sh — markdown topic files → config (no-op if no topics)
#   5. merge-configs.sh — assembles final openclaw.json (overrides any onboard defaults)
#   6. deploy workspace bootstrap files + skills + topics
#   7. print restart command

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_LOCAL="$SCRIPT_DIR/.env.local"

if [[ ! -f "$ENV_LOCAL" ]]; then
  echo "error: $ENV_LOCAL not found." >&2
  echo "First run:  cp .env.example .env.local" >&2
  echo "Then edit .env.local with TELEGRAM_BOT_TOKEN, TELEGRAM_OWNER_ID, and your provider API key." >&2
  exit 1
fi

# Source env so this script + child scripts see the values
set -a; source "$ENV_LOCAL"; set +a

# Validate required values are real (not CHANGE_ME)
require_var() {
  local var="$1"
  local val="${!var:-}"
  if [[ -z "$val" || "$val" == "CHANGE_ME" ]]; then
    echo "error: $var is unset or CHANGE_ME in .env.local" >&2
    exit 1
  fi
}
require_var TELEGRAM_BOT_TOKEN
require_var TELEGRAM_OWNER_ID

# Find which provider API key is set
PROVIDER_KEY_VAR=""
for var in ANTHROPIC_API_KEY OPENAI_API_KEY MINIMAX_API_KEY GOOGLE_API_KEY GEMINI_API_KEY CEREBRAS_API_KEY GROQ_API_KEY XAI_API_KEY; do
  v="${!var:-}"
  if [[ -n "$v" && "$v" != "CHANGE_ME" ]]; then
    PROVIDER_KEY_VAR="$var"
    break
  fi
done
if [[ -z "$PROVIDER_KEY_VAR" ]]; then
  echo "error: no provider API key set in .env.local." >&2
  echo "Add one of: ANTHROPIC_API_KEY, OPENAI_API_KEY, MINIMAX_API_KEY, etc." >&2
  exit 1
fi

echo "=== bootstrap (provider: $PROVIDER_KEY_VAR) ==="

# 1. system install: OpenClaw + TaskFlow + Mission Control
echo
echo "[1/6] system install"
"$SCRIPT_DIR/setup-openclaw.sh"

# 2. openclaw onboard non-interactively (daemon + workspace + initial config)
echo
echo "[2/6] openclaw onboard --non-interactive"
if [[ ! -f "$HOME/.openclaw/openclaw.json" ]]; then
  # --accept-risk required for non-interactive: acknowledges API keys + daemon
  # run unattended without per-prompt warnings. See docs.openclaw.ai/security
  openclaw onboard \
    --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice apiKey \
    --secret-input-mode ref \
    --custom-api-key "$PROVIDER_KEY_VAR" \
    --install-daemon \
    || { echo "openclaw onboard failed; check flags against your installed version" >&2; exit 1; }
else
  echo "(skipping — ~/.openclaw/openclaw.json already exists)"
fi

# 3. agent identity onboard (non-interactive)
echo
echo "[3/6] agent identity setup"
"$SCRIPT_DIR/onboard-agent.sh" --non-interactive

# 4. sync topics
echo
echo "[4/6] sync topics"
"$SCRIPT_DIR/sync-topics.sh"

# 5. merge configs (this overwrites openclaw.json with our shape)
echo
echo "[5/6] merge configs"
"$SCRIPT_DIR/merge-configs.sh"

# 6. deploy workspace bootstrap + skills + topics
echo
echo "[6/6] deploy workspace"
mkdir -p "$HOME/.openclaw/workspace"
rsync -av --exclude='*.template' --exclude='_TEMPLATE.md' \
  "$SCRIPT_DIR/workspace/" "$HOME/.openclaw/workspace/" >/dev/null

echo
echo "=== bootstrap complete ==="
echo "Restart gateway: launchctl kickstart -k gui/\$UID/openclaw"
echo "  or:            openclaw gateway restart"
echo "Mission Control: http://localhost:3000  (token in .env.local: \$MC_API_KEY)"
