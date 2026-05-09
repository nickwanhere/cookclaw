#!/usr/bin/env bash
set -euo pipefail

# System install for OpenClaw on macOS. Idempotent: re-running is safe.
# Does NOT touch ~/.openclaw/openclaw.json — that's merge-configs.sh's job.

require() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1 ($2)"; exit 1; }; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "this setup is macOS-only; current platform: $(uname -s)" >&2
  exit 1
fi

require brew  "install from https://brew.sh"
require node  "brew install node  OR  install nvm and 'nvm install --lts'"
require npm   "comes with node"
require jq    "brew install jq"

if ! command -v openclaw >/dev/null 2>&1; then
  echo "installing openclaw globally via npm..."
  npm i -g openclaw
else
  echo "openclaw already installed: $(openclaw --version 2>/dev/null || echo unknown)"
fi

# TaskFlow: owner-curated task layer (markdown source of truth + SQLite index)
TASKFLOW_DIR="$HOME/.openclaw/taskflow"
if [[ ! -d "$TASKFLOW_DIR" ]]; then
  echo "installing taskflow..."
  git clone --depth=1 https://github.com/auxclawdbot/taskflow "$TASKFLOW_DIR"
  if [[ -d /opt/homebrew/bin ]]; then
    ln -sf "$TASKFLOW_DIR/scripts/taskflow-cli.mjs" /opt/homebrew/bin/taskflow
  elif [[ -d /usr/local/bin ]]; then
    ln -sf "$TASKFLOW_DIR/scripts/taskflow-cli.mjs" /usr/local/bin/taskflow
  else
    echo "warning: neither /opt/homebrew/bin nor /usr/local/bin present — symlink taskflow manually" >&2
  fi
  ( cd "$TASKFLOW_DIR" && npm install >/dev/null 2>&1 )
  echo "taskflow installed at $TASKFLOW_DIR"
else
  echo "taskflow already installed: $TASKFLOW_DIR"
fi

# Mission Control: local ops dashboard (builderz-labs). Runs at http://localhost:3000
# Per-install local — agent talks to MC via outbound HTTP with bearer token.
MC_DIR="$HOME/.openclaw/mission-control"
SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_LOCAL="$SETUP_DIR/.env.local"

if [[ ! -d "$MC_DIR" ]]; then
  echo "installing mission-control (local dashboard)..."
  git clone --depth=1 https://github.com/builderz-labs/mission-control "$MC_DIR" \
    || { echo "warning: mission-control clone failed" >&2; }

  if [[ -d "$MC_DIR" ]]; then
    # pnpm 11 exits non-zero on ERR_PNPM_IGNORED_BUILDS even when install succeeds.
    # We deliberately ignore install.sh's exit code and rely on `pnpm rebuild`
    # (next step) to force native compiles, then hard-verify below.
    ( cd "$MC_DIR" && bash install.sh --local 2>&1 | tail -10 ) || true

    # Force native postinstall scripts to run (better-sqlite3, etc.).
    # pnpm 11's onlyBuiltDependencies gate doesn't apply to `pnpm rebuild`.
    if [[ -f "$MC_DIR/package.json" ]]; then
      ( cd "$MC_DIR" && pnpm rebuild 2>&1 | tail -5 ) \
        || echo "warning: pnpm rebuild failed; native modules may not work" >&2
    fi

    # Hard-verify better-sqlite3 actually loads. MC crashes silently if it doesn't.
    if [[ -f "$MC_DIR/package.json" ]]; then
      if ! ( cd "$MC_DIR" && node -e "require('better-sqlite3')" 2>/dev/null ); then
        echo "ERROR: better-sqlite3 still not loadable after pnpm rebuild." >&2
        echo "  Try manually: cd $MC_DIR && pnpm rebuild better-sqlite3" >&2
        echo "  Or check Node version mismatch: node -v" >&2
      else
        echo "verified: better-sqlite3 loads correctly"
      fi
    fi
  fi
else
  echo "mission-control already installed: $MC_DIR"
fi

# Start MC in background if not already on :3000
if ! lsof -i :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
  if [[ -f "$MC_DIR/package.json" ]] && command -v pnpm >/dev/null 2>&1; then
    echo "starting mission-control (cold Next.js compile can take 30-60s)..."
    ( cd "$MC_DIR" && nohup pnpm dev > "$MC_DIR/dev.log" 2>&1 & )
    # Next.js dev cold start is slow — give it up to 60s
    for i in $(seq 1 60); do
      sleep 1
      if lsof -i :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "mission-control running at http://localhost:3000 (logs: $MC_DIR/dev.log) [bound in ${i}s]"
        break
      fi
    done
    if ! lsof -i :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
      echo "warning: mission-control did not bind :3000 within 60s" >&2
      echo "--- last 30 lines of $MC_DIR/dev.log ---" >&2
      tail -30 "$MC_DIR/dev.log" >&2 || true
      echo "--- end dev.log ---" >&2
    fi
  fi
else
  echo "mission-control already running on :3000"
fi

# Extract or generate MC API key, write to .env.local
mc_extract_or_generate_key() {
  local mc_env="$MC_DIR/.env"
  if [[ -f "$mc_env" ]]; then
    # Try common variable names MC's install.sh might use
    for var in MC_API_KEY API_KEY ADMIN_TOKEN BEARER_TOKEN ADMIN_API_KEY; do
      local val
      val=$(grep -E "^$var=" "$mc_env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
      if [[ -n "$val" && "$val" != "CHANGE_ME" ]]; then
        printf '%s' "$val"
        return 0
      fi
    done
  fi
  # Fallback: generate our own. MC may need this set in its .env too — owner ties them up.
  openssl rand -hex 32
}

upsert_env_var() {
  local var="$1" val="$2" file="$3"
  if [[ ! -f "$file" ]]; then return 1; fi
  if grep -q "^$var=" "$file"; then
    sed -i.bak "s|^$var=.*|$var=$val|" "$file" && rm -f "$file.bak"
  else
    echo "$var=$val" >> "$file"
  fi
}

if [[ -f "$ENV_LOCAL" ]]; then
  MC_KEY="$(mc_extract_or_generate_key)"
  upsert_env_var MC_URL "http://localhost:3000" "$ENV_LOCAL"
  upsert_env_var MC_API_KEY "$MC_KEY" "$ENV_LOCAL"
  echo "wrote MC_URL + MC_API_KEY to $ENV_LOCAL"
  echo "  MC dashboard: http://localhost:3000  (override URL for tailscale later)"
  if [[ -f "$MC_DIR/.env" ]] && ! grep -q "^MC_API_KEY=$MC_KEY" "$MC_DIR/.env" 2>/dev/null; then
    echo "  note: if MC's own .env uses a different key var, ensure $MC_DIR/.env matches MC_API_KEY in $ENV_LOCAL"
  fi
else
  echo "note: $ENV_LOCAL not found yet — cp .env.example .env.local and re-run, or fill MC_URL/MC_API_KEY manually"
fi

echo
echo
echo "system install complete (OpenClaw + TaskFlow + Mission Control)."
echo "If you ran this directly, finish setup with: ./bootstrap.sh"
echo "(if invoked via bootstrap.sh, it continues automatically)"
