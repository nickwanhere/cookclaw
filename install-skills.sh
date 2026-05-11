#!/usr/bin/env bash
set -uo pipefail

# Install binaries for the bundled OpenClaw skills our template uses.
# Try `openclaw skills install` first (if available); fall back to brew/npm.
#
# Skills enabled by config/01a-skills.json:
#   clawhub        — ClawHub CLI for skill marketplace browsing       (npm)
#   mcporter       — MCP server bridge                                (npm)
#   obsidian       — read/write Obsidian vault                        (brew: obsidian-cli)
#   session-logs   — agent session log queries                        (brew: ripgrep)
#   summarize      — text summarization wrapper                       (brew, possibly steipete tap)
#   tmux           — terminal multiplexer for agent-driving-agent     (brew)
#   video-frames   — extract frames from video                        (brew: ffmpeg)
#   wacli          — WhatsApp CLI                                     (brew, possibly steipete tap)
#   xurl           — better curl                                      (brew, possibly steipete tap)
#   coding-agent   — agent-as-coding-assistant                        (npm: @anthropic-ai/claude-code)
#   model-usage    — model usage tracking                             (brew --cask: codexbar)
#
# Usage: ./install-skills.sh

command -v brew >/dev/null 2>&1 || { echo "missing: brew (https://brew.sh)" >&2; exit 1; }
command -v npm  >/dev/null 2>&1 || { echo "missing: npm" >&2; exit 1; }

# Try OpenClaw's built-in skill installer first if it exists
if openclaw skills install --help >/dev/null 2>&1; then
  echo "using openclaw skills install for known skills..."
  for skill in clawhub mcporter obsidian session-logs summarize tmux video-frames wacli xurl coding-agent model-usage; do
    echo "  installing: $skill"
    openclaw skills install "$skill" 2>&1 | tail -3 || echo "  (continuing despite error)"
  done
  echo
  echo "Done via 'openclaw skills install'. If any failed, manual install commands below:"
fi

echo
echo "=== manual install (brew / npm) ==="

brew_install() {
  local pkg="$1"
  if brew list "$pkg" >/dev/null 2>&1; then
    echo "  brew: $pkg already installed"
  else
    echo "  brew install $pkg"
    brew install "$pkg" 2>&1 | tail -2 || echo "    (brew failed; may need a tap — try 'brew tap steipete/tap' first)"
  fi
}

brew_cask_install() {
  local pkg="$1"
  if brew list --cask "$pkg" >/dev/null 2>&1; then
    echo "  brew cask: $pkg already installed"
  else
    echo "  brew install --cask $pkg"
    brew install --cask "$pkg" 2>&1 | tail -2 || echo "    (brew cask failed)"
  fi
}

npm_install() {
  local pkg="$1"
  if npm list -g "$pkg" --depth=0 >/dev/null 2>&1; then
    echo "  npm: $pkg already installed"
  else
    echo "  npm i -g $pkg"
    npm i -g "$pkg" 2>&1 | tail -2 || echo "    (npm failed)"
  fi
}

# Standard brew packages
brew_install obsidian-cli
brew_install ripgrep        # session-logs needs rg
brew_install tmux
brew_install ffmpeg         # video-frames

# Likely in steipete tap — auto-tap if needed
if ! brew tap | grep -q "steipete/tap"; then
  echo "  brew tap steipete/tap"
  brew tap steipete/tap 2>&1 | tail -2 || echo "    (tap failed; try manually)"
fi
brew_install summarize
brew_install wacli
brew_install xurl

# Peekaboo (steipete/peekaboo) — macOS screen capture + GUI automation,
# exposed to OpenClaw via MCP. Requires Screen Recording + Accessibility
# permissions granted to the binary — owner-approved once on first launch.
brew_install peekaboo

# Brew cask
brew_cask_install codexbar  # model-usage

# npm packages
npm_install clawhub
npm_install mcporter
npm_install @anthropic-ai/claude-code  # coding-agent

echo
echo "=== community skills ==="

# Self-improvement skill (peterskoett/self-improving-agent).
# Appends learnings/errors/feature-requests to workspace/.learnings/ — the
# active-capture half of self-improvement. Dreaming (memory-core plugin)
# reads these on each cycle and promotes patterns to MEMORY.md.
install_self_improvement_skill() {
  local target="$HOME/.openclaw/workspace/skills/self-improvement"

  # Try ClawHub first (faster, version-pinned by registry)
  if command -v clawhub >/dev/null 2>&1; then
    if clawhub install self-improving-agent 2>&1 | tail -3 | grep -qiE "installed|already"; then
      echo "  self-improvement: installed via clawhub"
      return 0
    fi
  fi

  # Fallback: git clone the upstream repo
  if [[ -d "$target/.git" ]]; then
    echo "  self-improvement: already cloned, pulling latest"
    ( cd "$target" && git pull --quiet 2>&1 | tail -2 ) || echo "    (pull failed; continuing)"
  elif [[ -d "$target" ]]; then
    echo "  self-improvement: dir exists without .git; leaving as-is"
  else
    echo "  self-improvement: git clone github.com/peterskoett/self-improving-agent"
    git clone --depth=1 --quiet \
      https://github.com/peterskoett/self-improving-agent.git "$target" 2>&1 | tail -2 \
      || echo "    (clone failed; install manually if needed)"
  fi
}
install_self_improvement_skill

echo
echo "=== macOS permissions reminder ==="
if command -v peekaboo >/dev/null 2>&1; then
  echo "Peekaboo is installed but needs OS permissions BEFORE the agent can use it:"
  echo "  1. System Settings → Privacy & Security → Screen & System Audio Recording → allow 'peekaboo' (or Terminal/iTerm if running there)"
  echo "  2. System Settings → Privacy & Security → Accessibility → allow 'peekaboo'"
  echo "  Without these, screen capture + GUI automation will silently fail."
fi

echo
echo "=== verify ==="
echo "Run: openclaw doctor"
echo "Skills should appear under 'Eligible' instead of 'Missing requirements'."
echo "If any still listed as missing, check the binary path with: which <bin>"
