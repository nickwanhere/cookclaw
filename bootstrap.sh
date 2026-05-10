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
echo "[1/9] system install"
"$SCRIPT_DIR/setup-openclaw.sh"

# Symlink .env.local → ~/.openclaw/.env so the daemon can read env vars after restart/reboot.
# OpenClaw auto-loads this file at gateway start (process env → cwd .env → ~/.openclaw/.env → config env block).
mkdir -p "$HOME/.openclaw"
if [[ -L "$HOME/.openclaw/.env" || -f "$HOME/.openclaw/.env" ]]; then
  rm -f "$HOME/.openclaw/.env"
fi
ln -sf "$ENV_LOCAL" "$HOME/.openclaw/.env"
echo "linked $HOME/.openclaw/.env → $ENV_LOCAL (daemon reads this on restart)"

# 2. openclaw onboard non-interactively (daemon + workspace + initial config)
echo
echo "[2/9] openclaw onboard --non-interactive"
if [[ ! -f "$HOME/.openclaw/openclaw.json" ]]; then
  # Sanity check: env var must be exported for the case below to read it
  if [[ -z "${!PROVIDER_KEY_VAR:-}" ]]; then
    echo "error: $PROVIDER_KEY_VAR is not in process env after sourcing .env.local" >&2
    echo "Check .env.local syntax (no quotes around the value, no leading whitespace)" >&2
    exit 1
  fi

  # Map our env var name to OpenClaw's provider-specific onboard flag + auth-choice.
  # Verified against `openclaw onboard --help` for v2026.5.7. Update as new providers
  # are supported. Note: --auth-choice 'apiKey' is the generic for anthropic (no
  # anthropic-specific auth-choice exists in this OpenClaw version).
  case "$PROVIDER_KEY_VAR" in
    ANTHROPIC_API_KEY)             AUTH_CHOICE="apiKey";              PROVIDER_FLAG="--anthropic-api-key" ;;
    OPENAI_API_KEY)                AUTH_CHOICE="openai-api-key";      PROVIDER_FLAG="--openai-api-key" ;;
    MINIMAX_API_KEY)               AUTH_CHOICE="minimax-global-api";  PROVIDER_FLAG="--minimax-api-key" ;;
    GOOGLE_API_KEY|GEMINI_API_KEY) AUTH_CHOICE="gemini-api-key";      PROVIDER_FLAG="--gemini-api-key" ;;
    CEREBRAS_API_KEY)              AUTH_CHOICE="cerebras-api-key";    PROVIDER_FLAG="--cerebras-api-key" ;;
    GROQ_API_KEY)                  AUTH_CHOICE="groq-api-key";        PROVIDER_FLAG="--groq-api-key" ;;
    XAI_API_KEY)                   AUTH_CHOICE="apiKey";              PROVIDER_FLAG="--xai-api-key" ;;
    *)
      echo "error: unsupported provider key var: $PROVIDER_KEY_VAR" >&2
      echo "Add a case statement entry for it (run 'openclaw onboard --help' for valid flags)" >&2
      exit 1
      ;;
  esac

  # --secret-input-mode ref persists key as env-ref (no plaintext in openclaw.json).
  # --skip-* flags tell onboard to leave things we own (workspace, channels, skills)
  # alone — we deploy them ourselves via rsync + merge-configs.sh.
  openclaw onboard \
    --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice "$AUTH_CHOICE" \
    "$PROVIDER_FLAG" "${!PROVIDER_KEY_VAR}" \
    --secret-input-mode ref \
    --node-manager npm \
    --skip-bootstrap \
    --skip-channels \
    --skip-skills \
    --skip-ui \
    --install-daemon \
    || { echo "openclaw onboard failed. Run 'openclaw onboard --help' and check flag set for v$(openclaw --version 2>/dev/null)" >&2; exit 1; }
else
  echo "(skipping — ~/.openclaw/openclaw.json already exists)"
fi

# 3. agent identity onboard (non-interactive)
echo
echo "[3/9] agent identity setup"
"$SCRIPT_DIR/onboard-agent.sh" --non-interactive

# 4. sync topics
echo
echo "[4/9] sync topics"
"$SCRIPT_DIR/sync-topics.sh"

# 5. merge configs (this overwrites openclaw.json with our shape)
echo
echo "[5/9] merge configs"
"$SCRIPT_DIR/merge-configs.sh"

# 6. deploy workspace bootstrap + skills + topics
echo
echo "[6/9] deploy workspace"
mkdir -p "$HOME/.openclaw/workspace"
rsync -av --exclude='*.template' --exclude='_TEMPLATE.md' \
  "$SCRIPT_DIR/workspace/" "$HOME/.openclaw/workspace/" >/dev/null

# 7. install bundled skill binaries (mcporter, clawhub, obsidian-cli, etc.)
# Skip with: SKIP_SKILLS=1 ./bootstrap.sh
echo
echo "[7/9] install bundled skill binaries"
if [[ "${SKIP_SKILLS:-0}" == "1" ]]; then
  echo "(skipped — SKIP_SKILLS=1 set)"
else
  "$SCRIPT_DIR/install-skills.sh" 2>&1 | sed 's/^/  /'
fi

# 8. scaffold vault layout (idempotent — never overwrites owner content)
# Creates the 5 memory-wiki folders + Logs/ + WIKI.md + index.md if missing.
# Skips if VAULT_PATH is unset (shouldn't happen — onboard-agent.sh defaults it).
echo
echo "[8/9] scaffold vault layout"
VAULT="${VAULT_PATH:-$HOME/.openclaw/wiki/main}"
mkdir -p "$VAULT"
SCAFFOLD="$SCRIPT_DIR/vault-scaffold"
if [[ -d "$SCAFFOLD" ]]; then
  for f in entities concepts syntheses sources reports Logs; do
    mkdir -p "$VAULT/$f"
  done
  # Copy WIKI.md / index.md only if missing — never overwrite owner edits
  for f in WIKI.md index.md; do
    if [[ ! -f "$VAULT/$f" && -f "$SCAFFOLD/$f" ]]; then
      cp "$SCAFFOLD/$f" "$VAULT/$f"
      echo "  scaffolded $f"
    fi
  done
  echo "  vault layout ready at $VAULT (folders ensured; WIKI.md/index.md only on first run)"
else
  echo "  (no vault-scaffold/ in repo; skipped)"
fi

# 9. register agent with mission-control so it appears in the dashboard
# immediately (without waiting for the first heartbeat tick).
# Idempotent: POST /api/agents/register returns existing entry on name match.
echo
echo "[9/9] register agent with mission-control"
if [[ -x "$SCRIPT_DIR/tests/test-mc-ping.sh" ]] && lsof -i :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
  AGENT_NAME=$(jq -r '.agent_name // empty' "$SCRIPT_DIR/profile.local.json" 2>/dev/null)
  AGENT_NAME="${AGENT_NAME:-cookclaw}"
  if "$SCRIPT_DIR/tests/test-mc-ping.sh" "$AGENT_NAME" 2>&1 | sed 's/^/  /'; then
    echo "  ok — agent '$AGENT_NAME' registered + heartbeat acknowledged"
  else
    echo "  warning: MC registration failed; run ./tests/test-mc-ping.sh manually to debug" >&2
  fi
else
  echo "  (skipped — MC not running on :3000 or test-mc-ping.sh missing)"
fi

echo
echo "=== bootstrap complete ==="
echo
echo "Restart gateway:"
echo "  launchctl kickstart -k gui/\$UID/openclaw"
echo "  (or: openclaw gateway restart)"
echo
echo "Recommended one-time cleanup (disables remaining unused bundled skills):"
echo "  openclaw doctor --fix"
echo
echo "Verify:"
echo "  openclaw doctor                     # should be all green"
echo "  http://localhost:3000               # Mission Control dashboard"
echo "  ./tests/test-mc-ping.sh             # standalone MC integration test"
echo "  Then DM your bot on Telegram (try: /mc-ping for MC heartbeat, /work for task summary)."
echo
echo "If doctor flags 'System Node 22 LTS not found' (you have nvm Node):"
echo "  brew install node@22 && brew link node@22 --force --overwrite"
echo "  openclaw gateway install --force    # relink daemon to brew Node"
