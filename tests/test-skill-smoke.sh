#!/usr/bin/env bash
# Skill staleness detector. Runs each workspace/skills/<name>/smoke.sh (if present),
# with a per-skill timeout, and logs failures so the agent surfaces them in the next
# daily rollup.
#
# Why: skills rot. Paths shift, tool flags change, account rules change, dependencies
# get uninstalled. A skill that was correct three months ago can fail silently — the
# self-improvement loop captures NEW learnings, this script catches OLD ones going bad.
#
# Wire-up: schedule via OpenClaw cron, weekly Sunday 04:00 (low-traffic slot):
#   openclaw cron add --name=skill-smoke --schedule="0 4 * * 0" \
#     --cmd="$OPENCLAW_AGENT_DIR/tests/test-skill-smoke.sh"
# Or run manually: bash tests/test-skill-smoke.sh
#
# Convention:
#   - A skill at workspace/skills/<name>/ MAY include smoke.sh.
#   - Smokes are optional — skills with no external state (pure-prompt skills like clarify)
#     don't need one.
#   - smoke.sh exits 0 on healthy, non-zero on rot, with a one-line stderr explaining why.
#   - Smokes must complete in under SKILL_SMOKE_TIMEOUT seconds (default 30).
#   - Smokes MUST be read-only — never mutate state. Use the existing skill's lighter
#     "am I reachable / does my dep exist" path, not the full integration test.
#
# Failure handling:
#   - Failed smokes do NOT auto-uninstall the skill. They append to .learnings/ERRORS.md.
#   - The agent surfaces failures in the next /work or daily rollup.
#   - Owner decides whether to fix, replace, or retire.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$SCRIPT_DIR/workspace/skills"
ERRORS_LOG="$SCRIPT_DIR/workspace/.learnings/ERRORS.md"
SKILL_SMOKE_TIMEOUT="${SKILL_SMOKE_TIMEOUT:-30}"

# macOS doesn't ship GNU timeout. Prefer gtimeout (coreutils via brew), fall back to a
# bash-native timeout wrapper.
run_with_timeout() {
  local secs="$1"; shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  else
    # bash-native fallback: background, sleep, kill
    "$@" &
    local pid=$!
    ( sleep "$secs" && kill -TERM "$pid" 2>/dev/null ) &
    local watcher=$!
    wait "$pid" 2>/dev/null; local rc=$?
    kill "$watcher" 2>/dev/null || true
    return "$rc"
  fi
}

log_failure() {
  local skill="$1" rc="$2" output="$3"
  local datestamp; datestamp="$(date '+%Y%m%d')"
  local isots; isots="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  local err_id="ERR-${datestamp}-SR-${skill}"
  mkdir -p "$(dirname "$ERRORS_LOG")"

  # Match the established ERRORS.md entry schema:
  # ## [ERR-YYYYMMDD-XXX] skill_or_command_name
  # **Logged**: / **Priority**: / **Status**: / **Area**: / ### sections / ---
  {
    echo ""
    echo "## [$err_id] $skill (skill-smoke)"
    echo ""
    echo "**Logged**: $isots"
    echo "**Priority**: high"
    echo "**Status**: pending"
    echo "**Area**: tests"
    echo ""
    echo "### Summary"
    echo "Weekly skill-smoke detected rot in \`$skill\`. The skill's preconditions are no longer met."
    echo ""
    echo "### Command"
    echo "\`bash workspace/skills/$skill/smoke.sh\`"
    echo ""
    echo "### Expected"
    echo "Exit code 0 — skill's runtime preconditions intact."
    echo ""
    echo "### Actual"
    echo "Exit code \`$rc\`. Smoke output:"
    echo '```'
    echo "$output"
    echo '```'
    echo ""
    echo "### Suggested Action"
    echo "Owner review: fix the skill, replace its dependency, or retire it. Failed smokes do NOT auto-uninstall — manual decision required."
    echo ""
    echo "---"
  } >> "$ERRORS_LOG"
}

PASS=0; FAIL=0; SKIP=0
declare -a FAILURES=()

echo "=== skill smoke run ==="
echo "skills dir: $SKILLS_DIR"
echo "timeout:    ${SKILL_SMOKE_TIMEOUT}s per skill"
echo

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "✗ skills dir missing: $SKILLS_DIR" >&2
  exit 1
fi

for skill_dir in "$SKILLS_DIR"/*/; do
  skill="$(basename "$skill_dir")"
  smoke="$skill_dir/smoke.sh"

  if [[ ! -f "$smoke" ]]; then
    printf "  · %-20s no smoke.sh (skipped)\n" "$skill"
    SKIP=$((SKIP+1))
    continue
  fi

  if [[ ! -x "$smoke" ]]; then
    printf "  ✗ %-20s smoke.sh not executable — chmod +x required\n" "$skill"
    FAIL=$((FAIL+1))
    FAILURES+=("$skill: smoke.sh not executable")
    log_failure "$skill" 126 "smoke.sh exists but is not executable (mode bits missing)"
    continue
  fi

  output="$(run_with_timeout "$SKILL_SMOKE_TIMEOUT" bash "$smoke" 2>&1)"
  rc=$?

  if [[ $rc -eq 0 ]]; then
    printf "  ✓ %-20s healthy\n" "$skill"
    PASS=$((PASS+1))
  elif [[ $rc -eq 124 || $rc -eq 143 ]]; then
    printf "  ✗ %-20s TIMEOUT after %ss\n" "$skill" "$SKILL_SMOKE_TIMEOUT"
    FAIL=$((FAIL+1))
    FAILURES+=("$skill: smoke timed out after ${SKILL_SMOKE_TIMEOUT}s")
    log_failure "$skill" "$rc" "smoke.sh exceeded ${SKILL_SMOKE_TIMEOUT}s timeout. Last output:\n$output"
  else
    printf "  ✗ %-20s rc=%d\n" "$skill" "$rc"
    FAIL=$((FAIL+1))
    FAILURES+=("$skill: rc=$rc")
    log_failure "$skill" "$rc" "$output"
  fi
done

echo
echo "=== summary ==="
echo "  passed:  $PASS"
echo "  failed:  $FAIL"
echo "  skipped: $SKIP (no smoke.sh)"

if [[ $FAIL -gt 0 ]]; then
  echo
  echo "failures:"
  printf '  - %s\n' "${FAILURES[@]}"
  echo
  echo "logged to: $ERRORS_LOG"
  exit 1
fi
