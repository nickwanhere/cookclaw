#!/usr/bin/env bash
set -uo pipefail

# Uninstall OpenClaw + TaskFlow + Mission Control + all install data.
# Keeps the template repo intact — only removes generated/installed artifacts.
#
# Usage:
#   ./uninstall-openclaw.sh           # interactive, confirms each destructive step
#   ./uninstall-openclaw.sh --force   # no prompts, blast everything

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

confirm() {
  if [[ $FORCE -eq 1 ]]; then return 0; fi
  read -r -p "$1 [y/N]: " ans
  [[ "$ans" =~ ^[Yy] ]]
}

echo "=== OpenClaw uninstall ==="
echo "Removes: OpenClaw + TaskFlow + Mission Control + ~/.openclaw + per-install state."
echo "Keeps: this repo's committed files (scripts, templates, configs)."
echo
if ! confirm "Proceed?"; then echo "aborted"; exit 0; fi

# 1. stop OpenClaw daemon + Mission Control
echo
if command -v openclaw >/dev/null 2>&1; then
  echo "stopping openclaw daemon (best effort)..."
  openclaw gateway stop 2>/dev/null || true
  launchctl unload "$HOME/Library/LaunchAgents/openclaw.plist" 2>/dev/null || true
  pkill -f "openclaw" 2>/dev/null || true
fi
# Kill any pnpm dev / next dev running for Mission Control
if lsof -i :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "stopping mission-control on :3000..."
  lsof -i :3000 -sTCP:LISTEN -t | xargs kill 2>/dev/null || true
fi

# 2. uninstall openclaw npm package
if command -v npm >/dev/null 2>&1; then
  if npm list -g openclaw --depth=0 >/dev/null 2>&1; then
    if confirm "Uninstall openclaw npm package globally?"; then
      npm uninstall -g openclaw 2>&1 | tail -3
    fi
  fi
fi

# 3. remove all OpenClaw state (config, workspace, taskflow clone, MC clone, vault, sessions)
if [[ -d "$HOME/.openclaw" ]]; then
  if confirm "Remove $HOME/.openclaw (all OpenClaw + TaskFlow + MC data)?"; then
    rm -rf "$HOME/.openclaw"
    echo "removed $HOME/.openclaw"
  fi
fi

# 4. remove taskflow symlink
for path in /opt/homebrew/bin/taskflow /usr/local/bin/taskflow; do
  if [[ -L "$path" ]]; then
    rm -f "$path" && echo "removed symlink $path"
  fi
done

# 4a. ~/.openclaw/.env symlink is removed when ~/.openclaw is wiped above; nothing to do here
# (kept for documentation — if step 3 was skipped, the symlink may still exist)
[[ -L "$HOME/.openclaw/.env" ]] && rm -f "$HOME/.openclaw/.env"

# 5. clean per-install state inside the template repo
# KEEP .env.local and profile.local.json — they hold secrets + wizard answers
# that the user typed once. Retest cycles reuse these via bootstrap.sh.
# For a TRUE clean slate (new owner, full reset), manually:
#   rm .env.local profile.local.json
echo
echo "cleaning generated state in $SCRIPT_DIR (keeping .env.local + profile.local.json)..."
rm -f "$SCRIPT_DIR/config/"*.local.json 2>/dev/null
rm -f "$SCRIPT_DIR/config/profile.local.json" 2>/dev/null  # legacy location, if present
rm -f "$SCRIPT_DIR/workspace/IDENTITY.md"
rm -f "$SCRIPT_DIR/workspace/USER.md"
find "$SCRIPT_DIR/workspace/topics" -name '*.md' ! -name '_TEMPLATE.md' -delete 2>/dev/null || true
rm -f "$SCRIPT_DIR/openclaw.json.bak."* 2>/dev/null

echo
echo "=== uninstall complete ==="
echo "Template intact at $SCRIPT_DIR (.env.local + profile.local.json kept for retest)."
echo "To reinstall: ./bootstrap.sh"
echo "For a true clean slate first: rm .env.local profile.local.json"
