#!/usr/bin/env bash
set -euo pipefail

# Interactive onboarding wizard. Per-install setup:
#   - Renders IDENTITY.md and USER.md from templates
#   - Generates config/00-provider.local.json (model provider, model IDs, API key SecretRef)
#   - Updates .env.local with TELEGRAM_OWNER_ID
#
# Idempotent: re-run to edit. Profile values persist to config/profile.local.json.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE="$SCRIPT_DIR/config/profile.local.json"
PROVIDER_CONFIG="$SCRIPT_DIR/config/00-provider.local.json"
WORKSPACE="$SCRIPT_DIR/workspace"
ENV_LOCAL="$SCRIPT_DIR/.env.local"

command -v jq >/dev/null 2>&1 || { echo "missing: jq (brew install jq)" >&2; exit 1; }

load_default() {
  local key="$1" fallback="$2"
  if [[ -f "$PROFILE" ]]; then
    jq -r --arg k "$key" --arg f "$fallback" '.[$k] // $f' "$PROFILE"
  else
    echo "$fallback"
  fi
}

prompt_field() {
  local label="$1" default="$2" required="${3:-0}" var
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

echo "=== OpenClaw agent onboarding ==="
echo "(answers persist to $PROFILE; re-run to edit)"
echo

echo "-- about you --"
USER_NAME="$(prompt_field 'Your name' "$(load_default user_name '')" 1)"
echo
USER_ROLE="$(prompt_field 'Your role (e.g. founder, marketer, designer)' "$(load_default user_role '')" 1)"
echo
TG_OWNER_ID="$(prompt_field 'Your Telegram numeric user ID (from @userinfobot)' "$(load_default telegram_owner_id '')" 1)"
if ! [[ "$TG_OWNER_ID" =~ ^[0-9]+$ ]]; then
  echo "error: Telegram user ID must be numeric digits only, got: $TG_OWNER_ID" >&2
  exit 1
fi

echo
echo "-- about the agent --"
AGENT_NAME="$(prompt_field 'Agent name' "$(load_default agent_name 'Liam')" 0)"
echo
AGENT_VIBE="$(prompt_field 'Agent vibe (one sentence)' "$(load_default agent_vibe 'direct, slightly sarcastic, helpful underneath')" 0)"

echo
echo "-- model provider --"
echo "Examples: openai, minimax, cerebras, google. Check OpenClaw docs for valid provider keys."
PROVIDER="$(prompt_field 'Provider key' "$(load_default provider 'openai')" 1)"
echo
echo "Model IDs use 'provider/model' format. Examples: openai/gpt-5, minimax/abab-7-chat."
MAIN_MODEL="$(prompt_field "Main agent model (full $PROVIDER/... ID)" "$(load_default main_model "$PROVIDER/")" 1)"
echo
echo "Active-memory fires before every reply — pick a cheap/fast model from the same provider."
ACTIVE_MODEL="$(prompt_field "Active-memory model" "$(load_default active_model "$PROVIDER/")" 1)"
echo
API_KEY_VAR="$(prompt_field 'API key environment variable name' "$(load_default api_key_var "$(echo "$PROVIDER" | tr '[:lower:]' '[:upper:]')_API_KEY")" 1)"

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
jq -n \
  --arg provider "$PROVIDER" \
  --arg main_model "$MAIN_MODEL" \
  --arg active_model "$ACTIVE_MODEL" \
  --arg api_key_var "$API_KEY_VAR" \
  '{
    agents: { defaults: { model: { primary: $main_model, fallbacks: [] } } },
    models: { providers: { ($provider): { apiKey: { source: "env", provider: "default", id: $api_key_var } } } },
    plugins: { entries: { "active-memory": { config: { model: $active_model } } } }
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
