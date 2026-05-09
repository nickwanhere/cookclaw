#!/usr/bin/env bash
set -euo pipefail

# Onboarding wizard. Per-install setup:
#   - Renders IDENTITY.md and USER.md from templates
#   - Generates config/00-provider.local.json (model provider, model IDs, API key SecretRef)
#   - Updates .env.local with TELEGRAM_OWNER_ID
#
# Modes:
#   ./onboard-agent.sh                  # interactive wizard
#   ./onboard-agent.sh --non-interactive  # skip prompts, use defaults from .env.local + profile + provider inference. Fails if required values missing.
#
# Idempotent: re-run to edit. Profile values persist to config/profile.local.json.

NON_INTERACTIVE=0
[[ "${1:-}" == "--non-interactive" ]] && NON_INTERACTIVE=1

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# profile.local.json holds wizard answers — NOT an openclaw config fragment.
# Lives at the repo root (not in config/) so merge-configs.sh doesn't pull it.
PROFILE="$SCRIPT_DIR/profile.local.json"
PROVIDER_CONFIG="$SCRIPT_DIR/config/00-provider.local.json"
WORKSPACE="$SCRIPT_DIR/workspace"
ENV_LOCAL="$SCRIPT_DIR/.env.local"

# Migrate old profile location if upgrading
OLD_PROFILE="$SCRIPT_DIR/config/profile.local.json"
if [[ -f "$OLD_PROFILE" && ! -f "$PROFILE" ]]; then
  mv "$OLD_PROFILE" "$PROFILE" 2>/dev/null && echo "migrated profile to $PROFILE"
fi

command -v jq >/dev/null 2>&1 || { echo "missing: jq (brew install jq)" >&2; exit 1; }

load_default() {
  local key="$1" fallback="$2"
  if [[ -f "$PROFILE" ]]; then
    jq -r --arg k "$key" --arg f "$fallback" '.[$k] // $f' "$PROFILE"
  else
    echo "$fallback"
  fi
}

# Read VAR=value from a .env-formatted file. Returns empty if missing, blank, or CHANGE_ME.
read_env_var() {
  local var_name="$1" file="$2"
  [[ -f "$file" ]] || { printf ''; return; }
  local val
  val=$(grep -E "^${var_name}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-)
  val="${val#\"}"; val="${val%\"}"
  val="${val#\'}"; val="${val%\'}"
  if [[ "$val" != "CHANGE_ME" && -n "$val" ]]; then printf '%s' "$val"; else printf ''; fi
}

# Find the first *_API_KEY var in .env.local with a real value, excluding MC_* / TELEGRAM_*.
infer_api_key_var() {
  local file="$1"
  [[ -f "$file" ]] || { printf ''; return; }
  while IFS= read -r line; do
    local var_name="${line%%=*}"
    local val="${line#*=}"
    val="${val#\"}"; val="${val%\"}"
    val="${val#\'}"; val="${val%\'}"
    case "$var_name" in MC_API_KEY|TELEGRAM_*) continue;; esac
    if [[ "$val" != "CHANGE_ME" && -n "$val" ]]; then printf '%s' "$var_name"; return; fi
  done < <(grep -E "^[A-Z][A-Z0-9_]*_API_KEY=" "$file" 2>/dev/null)
  printf ''
}

# Map an API key var name to a provider key (best-guess; user can override).
api_key_var_to_provider() {
  case "$1" in
    ANTHROPIC_*) echo "anthropic";;
    OPENAI_*) echo "openai";;
    MINIMAX_*) echo "minimax";;
    GOOGLE_*|GEMINI_*) echo "google";;
    CEREBRAS_*) echo "cerebras";;
    GROQ_*) echo "groq";;
    XAI_*) echo "xai";;
    *) echo "";;
  esac
}

# Verified-current default flagship model per provider (May 2026). Override anytime.
default_main_model_for() {
  case "$1" in
    openai) echo "openai/gpt-5";;
    anthropic) echo "anthropic/claude-sonnet-4-6";;
    minimax) echo "minimax/m2-7";;
    google) echo "google/gemini-3-pro";;
    cerebras) echo "cerebras/gpt-oss-120b";;
    groq) echo "groq/llama-4-70b";;
    xai) echo "xai/grok-4";;
    *) echo "$1/REPLACE_WITH_MODEL_ID";;
  esac
}

# Cheap/fast tier for active-memory (fires before every reply).
default_active_model_for() {
  case "$1" in
    openai) echo "openai/gpt-5-mini";;
    anthropic) echo "anthropic/claude-haiku-4-5";;
    minimax) echo "minimax/m2-7-highspeed";;
    google) echo "google/gemini-3-flash";;
    cerebras) echo "cerebras/gpt-oss-120b";;
    groq) echo "groq/llama-4-8b";;
    xai) echo "xai/grok-4-mini";;
    *) echo "$1/REPLACE_WITH_MODEL_ID";;
  esac
}

prompt_field() {
  local label="$1" default="$2" required="${3:-0}" var
  # Non-interactive: just return the default, fail if required-and-empty.
  if [[ $NON_INTERACTIVE -eq 1 ]]; then
    if [[ -z "$default" && "$required" == "1" ]]; then
      echo "error: '$label' is required but has no default in non-interactive mode" >&2
      exit 1
    fi
    printf '%s' "$default"
    return 0
  fi
  while true; do
    if [[ -n "$default" ]]; then
      read -r -p "$label [$default]: " var
      var="${var:-$default}"
    else
      read -r -p "$label: " var
    fi
    if [[ -z "$var" && "$required" == "1" ]]; then
      echo "  required" >&2
      continue
    fi
    printf '%s' "$var"
    return 0
  done
}

if [[ $NON_INTERACTIVE -eq 0 ]]; then
  echo "=== OpenClaw agent onboarding ==="
  echo "(answers persist to $PROFILE; re-run to edit)"
  echo
  echo "-- about you --"
fi

# In non-interactive mode, name/role default to generic placeholders if not in profile —
# the workspace owner is identified by TELEGRAM_OWNER_ID at runtime; name/role are cosmetic.
USER_NAME="$(prompt_field 'Your name' "$(load_default user_name 'Owner')" 0)"
USER_ROLE="$(prompt_field 'Your role (e.g. founder, marketer, designer)' "$(load_default user_role 'owner')" 0)"
[[ $NON_INTERACTIVE -eq 0 ]] && echo
ENV_TG_ID="$(read_env_var TELEGRAM_OWNER_ID "$ENV_LOCAL")"
TG_OWNER_ID="$(prompt_field 'Your Telegram numeric user ID (from @userinfobot)' "$(load_default telegram_owner_id "$ENV_TG_ID")" 1)"
if ! [[ "$TG_OWNER_ID" =~ ^[0-9]+$ ]]; then
  echo "error: Telegram user ID must be numeric digits only, got: $TG_OWNER_ID" >&2
  exit 1
fi

if [[ $NON_INTERACTIVE -eq 0 ]]; then
  echo
  echo "-- about the agent --"
fi
AGENT_NAME="$(prompt_field 'Agent name' "$(load_default agent_name 'Liam')" 0)"
AGENT_VIBE="$(prompt_field 'Agent vibe (one sentence)' "$(load_default agent_vibe 'direct, slightly sarcastic, helpful underneath')" 0)"

INFERRED_KEY_VAR="$(infer_api_key_var "$ENV_LOCAL")"
INFERRED_PROVIDER="$(api_key_var_to_provider "$INFERRED_KEY_VAR")"
if [[ $NON_INTERACTIVE -eq 0 ]]; then
  echo
  echo "-- model provider --"
  if [[ -n "$INFERRED_KEY_VAR" ]]; then
    echo "(detected $INFERRED_KEY_VAR in .env.local — using as default)"
  fi
  echo "Examples: openai, minimax, cerebras, google. Check OpenClaw docs for valid provider keys."
fi
PROVIDER="$(prompt_field 'Provider key' "$(load_default provider "${INFERRED_PROVIDER:-openai}")" 1)"
[[ $NON_INTERACTIVE -eq 0 ]] && echo "Model IDs use 'provider/model' format. Defaults below are verified-current picks per provider."
MAIN_MODEL="$(prompt_field "Main agent model" "$(load_default main_model "$(default_main_model_for "$PROVIDER")")" 1)"
[[ $NON_INTERACTIVE -eq 0 ]] && echo "Active-memory fires before every reply — cheap/fast tier."
ACTIVE_MODEL="$(prompt_field "Active-memory model" "$(load_default active_model "$(default_active_model_for "$PROVIDER")")" 1)"
DEFAULT_KEY_VAR="${INFERRED_KEY_VAR:-$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')_API_KEY}"
API_KEY_VAR="$(prompt_field 'API key environment variable name' "$(load_default api_key_var "$DEFAULT_KEY_VAR")" 1)"

# --- save profile ---
mkdir -p "$(dirname "$PROFILE")"
jq -n \
  --arg user_name "$USER_NAME" \
  --arg user_role "$USER_ROLE" \
  --arg agent_name "$AGENT_NAME" \
  --arg agent_vibe "$AGENT_VIBE" \
  --arg telegram_owner_id "$TG_OWNER_ID" \
  --arg provider "$PROVIDER" \
  --arg main_model "$MAIN_MODEL" \
  --arg active_model "$ACTIVE_MODEL" \
  --arg api_key_var "$API_KEY_VAR" \
  '{
    user_name: $user_name, user_role: $user_role, agent_name: $agent_name, agent_vibe: $agent_vibe, telegram_owner_id: $telegram_owner_id,
    provider: $provider, main_model: $main_model, active_model: $active_model, api_key_var: $api_key_var
  }' > "$PROFILE"
echo
echo "saved profile → $PROFILE"

# --- generate provider config fragment ---
# SecretRef syntax: { source, provider, id } — verified at docs.openclaw.ai
# Telegram allowFrom must be literal IDs (no SecretRefs in arrays), so resolved here.
jq -n \
  --arg provider "$PROVIDER" \
  --arg main_model "$MAIN_MODEL" \
  --arg active_model "$ACTIVE_MODEL" \
  --arg api_key_var "$API_KEY_VAR" \
  --arg tg_owner_id "$TG_OWNER_ID" \
  '{
    agents: { defaults: { model: { primary: $main_model, fallbacks: [] } } },
    models: { providers: { ($provider): { apiKey: { source: "env", provider: "default", id: $api_key_var } } } },
    plugins: { entries: { "active-memory": { config: { model: $active_model } } } },
    channels: { telegram: { allowFrom: [$tg_owner_id] } }
  }' > "$PROVIDER_CONFIG"
echo "generated $PROVIDER_CONFIG"

# --- render workspace templates ---
render_template() {
  local template="$1" output="$2"
  [[ -f "$template" ]] || { echo "error: template not found: $template" >&2; exit 1; }
  sed \
    -e "s|{{user_name}}|$USER_NAME|g" \
    -e "s|{{user_role}}|$USER_ROLE|g" \
    -e "s|{{agent_name}}|$AGENT_NAME|g" \
    -e "s|{{agent_vibe}}|$AGENT_VIBE|g" \
    -e "s|{{telegram_owner_id}}|$TG_OWNER_ID|g" \
    "$template" > "$output"
  echo "rendered $output"
}

render_template "$WORKSPACE/IDENTITY.md.template" "$WORKSPACE/IDENTITY.md"
render_template "$WORKSPACE/USER.md.template" "$WORKSPACE/USER.md"

# --- update .env.local ---
upsert_env() {
  local var="$1" val="$2" file="$3"
  if [[ ! -f "$file" ]]; then return 1; fi
  if grep -q "^$var=" "$file"; then
    sed -i.bak "s|^$var=.*|$var=$val|" "$file" && rm -f "$file.bak"
    echo "updated $var in $file"
  else
    echo "$var=$val" >> "$file"
    echo "appended $var to $file"
  fi
}

if [[ -f "$ENV_LOCAL" ]]; then
  upsert_env TELEGRAM_OWNER_ID "$TG_OWNER_ID" "$ENV_LOCAL"
  if ! grep -q "^$API_KEY_VAR=" "$ENV_LOCAL"; then
    echo "$API_KEY_VAR=CHANGE_ME" >> "$ENV_LOCAL"
    echo "appended $API_KEY_VAR placeholder to $ENV_LOCAL — fill in real key"
  fi
else
  echo
  echo "note: .env.local not found. cp .env.example .env.local and add:"
  echo "  TELEGRAM_OWNER_ID=$TG_OWNER_ID"
  echo "  $API_KEY_VAR=<real_key>"
fi

echo
echo "next: cp workspace/*.md ~/.openclaw/workspace/  (templates excluded by glob)"
echo "      ./merge-configs.sh --dry-run  to preview merged openclaw.json"
