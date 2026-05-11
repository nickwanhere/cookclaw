#!/usr/bin/env bash
# Test + benchmark suite for the openclawsetup template.
# Verifies everything testable without an actual OpenClaw install:
#   - JSON config validity, expected schema shape
#   - Shell script syntax, idempotency, error handling
#   - Sync script: markdown → JSON correctness, edge cases
#   - Bootstrap budget under cap
#   - Pipeline idempotency
# Outputs pass/fail counts + benchmark metrics for tracking health over time.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")"/.. && pwd)"
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0; FAIL=0
declare -a FAILURES=()
declare -a INSTALL_TIME_TODOS=()

# ---- assertion helpers ----
assert() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    PASS=$((PASS+1)); printf "  ✓ %s\n" "$desc"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$desc"); printf "  ✗ %s\n" "$desc"
  fi
}
assert_with_output() {
  local desc="$1"; shift
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [[ $rc -eq 0 ]]; then
    PASS=$((PASS+1)); printf "  ✓ %s\n" "$desc"
  else
    FAIL=$((FAIL+1)); FAILURES+=("$desc — $out"); printf "  ✗ %s\n    %s\n" "$desc" "$out"
  fi
}

# ---- static checks ----
echo "=== static ==="
test_config_json_valid() {
  for f in "$SCRIPT_DIR/config"/*.json; do jq empty "$f" >/dev/null 2>&1 || { echo "invalid: $f"; return 1; }; done
}
assert_with_output "all config/*.json parse as valid JSON" test_config_json_valid

test_scripts_syntax() {
  for f in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/tests/*.sh "$SCRIPT_DIR"/workspace/skills/*/smoke.sh; do
    [[ -e "$f" ]] || continue   # glob may not expand if no matches
    bash -n "$f" || { echo "syntax: $f"; return 1; }
  done
}
assert_with_output "all .sh files (template + tests + skill smokes) pass bash -n" test_scripts_syntax

test_required_files_exist() {
  for f in setup-openclaw.sh onboard-agent.sh merge-configs.sh sync-topics.sh uninstall-openclaw.sh bootstrap.sh install-skills.sh \
           tests/test-skill-smoke.sh \
           workspace/SOUL.md workspace/AGENTS.md workspace/HEARTBEAT.md \
           workspace/IDENTITY.md.template workspace/USER.md.template \
           workspace/topics/_TEMPLATE.md \
           workspace/skills/clarify/SKILL.md workspace/skills/work/SKILL.md \
           .env.example .gitignore; do
    [[ -e "$SCRIPT_DIR/$f" ]] || { echo "missing: $f"; return 1; }
  done
}
assert_with_output "all required template files exist" test_required_files_exist

test_skill_smokes_executable() {
  local count=0 problem=""
  for s in "$SCRIPT_DIR"/workspace/skills/*/smoke.sh; do
    [[ -e "$s" ]] || continue
    count=$((count+1))
    if [[ ! -x "$s" ]]; then
      problem="${problem}${s} not executable; "
    fi
  done
  if [[ -n "$problem" ]]; then echo "$problem"; return 1; fi
  [[ $count -gt 0 ]] || echo "(no smoke.sh files yet — convention is optional)"
  return 0
}
assert_with_output "all skill smoke.sh files are executable" test_skill_smokes_executable

test_soul_no_gendered_terms() {
  ! grep -qiE '\b(he|his|him|nick)\b' "$SCRIPT_DIR/workspace/SOUL.md"
}
assert "SOUL.md has no Nick-specific or gendered terms" test_soul_no_gendered_terms

test_bootstrap_under_cap() {
  # Real bootstrap bundle per workspace/AGENTS.md § "Sub-agent contract":
  # agents receive SOUL + AGENTS + IDENTITY + USER + TOOLS at boot. HEARTBEAT
  # loads per-tick, not at boot — measured separately by test_heartbeat_under_cap.
  # TOOLS.md isn't authored in the template (provided by OpenClaw at runtime from
  # registered tools/skills); measured as 0 here. If you later author one, add it
  # to the cat list.
  local cap; cap=$(jq -r '.agents.defaults.bootstrapMaxChars // 12000' "$SCRIPT_DIR/config/00-base.json")
  local actual; actual=$(cat \
    "$SCRIPT_DIR/workspace/SOUL.md" \
    "$SCRIPT_DIR/workspace/AGENTS.md" \
    "$SCRIPT_DIR/workspace/IDENTITY.md.template" \
    "$SCRIPT_DIR/workspace/USER.md.template" \
    2>/dev/null | wc -c | tr -d ' ')
  if [[ $actual -le $cap ]]; then return 0; else echo "$actual > $cap"; return 1; fi
}
assert_with_output "bootstrap (SOUL+AGENTS+IDENTITY+USER) under bootstrapMaxChars cap" test_bootstrap_under_cap

test_heartbeat_under_cap() {
  # HEARTBEAT.md loads on every ~10min tick = ~144x/day. Cap it at 3000 chars
  # to keep daily token burn modest. If you need more, split into multiple
  # heartbeat tasks (alternate hours) rather than bloating one file.
  local cap=3000
  local actual; actual=$(wc -c < "$SCRIPT_DIR/workspace/HEARTBEAT.md" 2>/dev/null | tr -d ' ')
  if [[ $actual -le $cap ]]; then return 0; else echo "$actual > $cap (~144x/day = ~$((actual*144/1000))k chars/day)"; return 1; fi
}
assert_with_output "HEARTBEAT.md under per-tick cap (3000 chars)" test_heartbeat_under_cap

test_tools_md_status() {
  # TOOLS.md is referenced by AGENTS.md sub-agent contract. If OpenClaw auto-
  # generates it from registered tools/skills, we don't author one here — but
  # the absence should be deliberate, not accidental. Flag for first-install
  # verification.
  if [[ -e "$SCRIPT_DIR/workspace/TOOLS.md" ]]; then
    return 0
  fi
  echo "(deferred: TOOLS.md not in template — confirm OpenClaw auto-generates from registered tools at first install)"
  return 0   # not a failure — informational
}
assert_with_output "TOOLS.md presence check (informational)" test_tools_md_status

# ---- merge-configs.sh behavior ----
echo
echo "=== merge-configs.sh ==="

test_merge_dryrun_valid_json() {
  ( cd "$SCRIPT_DIR" && ./merge-configs.sh --dry-run 2>/dev/null ) | jq empty
}
assert "merge --dry-run produces valid JSON" test_merge_dryrun_valid_json

test_merge_has_expected_top_keys() {
  local merged; merged=$( cd "$SCRIPT_DIR" && ./merge-configs.sh --dry-run 2>/dev/null )
  for k in gateway agents plugins channels; do
    echo "$merged" | jq -e ".$k" >/dev/null 2>&1 || { echo "missing top key: $k"; return 1; }
  done
}
assert_with_output "merged config has gateway/agents/plugins/channels at top level" test_merge_has_expected_top_keys

test_merge_telegram_uses_secretref() {
  local merged; merged=$( cd "$SCRIPT_DIR" && ./merge-configs.sh --dry-run 2>/dev/null )
  echo "$merged" | jq -e '.channels.telegram.botToken.source == "env"' >/dev/null
}
assert "telegram.botToken uses verified SecretRef shape (source: env)" test_merge_telegram_uses_secretref

test_merge_idempotent() {
  local a; a=$( cd "$SCRIPT_DIR" && ./merge-configs.sh --dry-run 2>/dev/null )
  local b; b=$( cd "$SCRIPT_DIR" && ./merge-configs.sh --dry-run 2>/dev/null )
  [[ "$a" == "$b" ]]
}
assert "merge --dry-run is deterministic / idempotent" test_merge_idempotent

# ---- sync-topics.sh behavior ----
echo
echo "=== sync-topics.sh ==="

test_sync_empty_dir_safe() {
  local out; out=$( cd "$SCRIPT_DIR" && ./sync-topics.sh --dry-run 2>/dev/null )
  echo "$out" | jq -e '._comment' >/dev/null
}
assert "sync --dry-run with no topics produces placeholder JSON" test_sync_empty_dir_safe

test_sync_skips_template() {
  local out; out=$( cd "$SCRIPT_DIR" && ./sync-topics.sh --dry-run 2>/dev/null )
  ! echo "$out" | jq -e '.channels.telegram.groups' >/dev/null 2>&1
}
assert "sync skips _TEMPLATE.md (no real topic produced)" test_sync_skips_template

test_sync_with_sample_topic() {
  local sample="$SCRIPT_DIR/workspace/topics/test-sync-sample.md"
  cat > "$sample" <<'EOF'
---
chat_id: -100888777
thread_id: 99
name: test sync sample
---
sample body content
EOF
  local out; out=$( cd "$SCRIPT_DIR" && ./sync-topics.sh --dry-run 2>/dev/null )
  rm -f "$sample"
  echo "$out" | jq -e '.channels.telegram.groups."-100888777".topics."99".systemPrompt' >/dev/null
}
assert "sync produces correctly-nested config for valid topic" test_sync_with_sample_topic

test_sync_skips_placeholder_ids() {
  local sample="$SCRIPT_DIR/workspace/topics/test-placeholder.md"
  cat > "$sample" <<'EOF'
---
chat_id: REPLACE_WITH_TELEGRAM_CHAT_ID
thread_id: REPLACE_WITH_TELEGRAM_THREAD_ID
---
body
EOF
  local out; out=$( cd "$SCRIPT_DIR" && ./sync-topics.sh --dry-run 2>/dev/null )
  rm -f "$sample"
  ! echo "$out" | jq -e '.channels.telegram.groups."REPLACE_WITH_TELEGRAM_CHAT_ID"' >/dev/null 2>&1
}
assert "sync skips topics with placeholder chat_id/thread_id" test_sync_skips_placeholder_ids

# ---- onboard-agent.sh behavior ----
echo
echo "=== onboard-agent.sh ==="

# Run onboard with mocked stdin in a sandbox — copy template to tmpdir, feed answers, verify outputs
test_onboard_creates_profile_and_renders() {
  local sandbox="$TMPDIR_ROOT/onboard-test"
  mkdir -p "$sandbox"
  cp -r "$SCRIPT_DIR"/* "$sandbox/" 2>/dev/null
  cp -r "$SCRIPT_DIR"/.env.example "$sandbox/.env.local"
  rm -f "$sandbox/config/00-provider.local.json" "$sandbox/profile.local.json"
  rm -f "$sandbox/workspace/IDENTITY.md" "$sandbox/workspace/USER.md"

  ( cd "$sandbox" && printf 'Test User\nDeveloper\n123456789\nLiam\ndefault vibe\nopenai\nopenai/gpt-5\nopenai/gpt-5-mini\nOPENAI_API_KEY\n' | ./onboard-agent.sh ) >/dev/null 2>&1

  [[ -f "$sandbox/profile.local.json" ]] || { echo "no profile created"; return 1; }
  [[ -f "$sandbox/config/00-provider.local.json" ]] || { echo "no provider config generated"; return 1; }
  [[ -f "$sandbox/workspace/IDENTITY.md" ]] || { echo "IDENTITY.md not rendered"; return 1; }
  [[ -f "$sandbox/workspace/USER.md" ]] || { echo "USER.md not rendered"; return 1; }
  grep -q "Test User" "$sandbox/workspace/USER.md" || { echo "USER.md missing user_name"; return 1; }
  grep -q "Liam" "$sandbox/workspace/IDENTITY.md" || { echo "IDENTITY.md missing agent_name"; return 1; }
  jq -e '.user_name == "Test User"' "$sandbox/profile.local.json" >/dev/null || { echo "profile missing user_name"; return 1; }
}
assert_with_output "onboard creates profile + renders IDENTITY.md/USER.md from mock input" test_onboard_creates_profile_and_renders

test_onboard_uses_env_local_defaults() {
  local sandbox="$TMPDIR_ROOT/onboard-env-defaults"
  mkdir -p "$sandbox"
  cp -r "$SCRIPT_DIR"/* "$sandbox/" 2>/dev/null

  # Pre-populate .env.local with real values — wizard should use them as defaults
  cat > "$sandbox/.env.local" <<'EOF'
TELEGRAM_BOT_TOKEN=real-bot-token
TELEGRAM_OWNER_ID=987654321
ANTHROPIC_API_KEY=sk-real-anthropic-key
EOF

  # answers: name, role, telegram_id(empty=accept env default), agent, vibe,
  #          provider(empty=inferred), main_model, active_model, api_key_var(empty=inferred)
  ( cd "$sandbox" && printf 'Test\nDev\n\nLiam\nvibe\n\nanthropic/claude-sonnet-4-6\nanthropic/claude-haiku-4-5\n\n' | ./onboard-agent.sh ) >/dev/null 2>&1

  jq -e '.telegram_owner_id == "987654321"' "$sandbox/profile.local.json" >/dev/null \
    || { echo "telegram_owner_id not pulled from .env.local"; return 1; }
  jq -e '.api_key_var == "ANTHROPIC_API_KEY"' "$sandbox/profile.local.json" >/dev/null \
    || { echo "api_key_var not inferred from .env.local"; return 1; }
  jq -e '.provider == "anthropic"' "$sandbox/profile.local.json" >/dev/null \
    || { echo "provider not inferred from api_key_var"; return 1; }
}
assert_with_output "onboard uses values already in .env.local as defaults (regression)" test_onboard_uses_env_local_defaults

test_onboard_non_interactive() {
  local sandbox="$TMPDIR_ROOT/onboard-non-interactive"
  mkdir -p "$sandbox"
  cp -r "$SCRIPT_DIR"/* "$sandbox/" 2>/dev/null

  cat > "$sandbox/.env.local" <<'EOF'
TELEGRAM_BOT_TOKEN=real-bot-token
TELEGRAM_OWNER_ID=987654321
ANTHROPIC_API_KEY=sk-real-anthropic-key
EOF

  # No stdin — fully non-interactive
  ( cd "$sandbox" && ./onboard-agent.sh --non-interactive </dev/null ) >/dev/null 2>&1

  jq -e '.telegram_owner_id == "987654321"' "$sandbox/profile.local.json" >/dev/null \
    || { echo "telegram_owner_id not picked up"; return 1; }
  jq -e '.provider == "anthropic"' "$sandbox/profile.local.json" >/dev/null \
    || { echo "provider not inferred"; return 1; }
  jq -e '.main_model == "anthropic/claude-sonnet-4-6"' "$sandbox/profile.local.json" >/dev/null \
    || { echo "main_model default not applied"; return 1; }
  jq -e '.api_key_var == "ANTHROPIC_API_KEY"' "$sandbox/profile.local.json" >/dev/null \
    || { echo "api_key_var not inferred"; return 1; }
  [[ -f "$sandbox/workspace/IDENTITY.md" ]] || { echo "IDENTITY.md not rendered"; return 1; }
  [[ -f "$sandbox/workspace/USER.md" ]] || { echo "USER.md not rendered"; return 1; }
}
assert_with_output "onboard --non-interactive works with .env.local + inference (no prompts)" test_onboard_non_interactive

test_onboard_rejects_non_numeric_telegram_id() {
  local sandbox="$TMPDIR_ROOT/onboard-bad-id"
  mkdir -p "$sandbox"
  cp -r "$SCRIPT_DIR"/* "$sandbox/" 2>/dev/null
  cp "$SCRIPT_DIR/.env.example" "$sandbox/.env.local"

  if ( cd "$sandbox" && printf 'Test\nRole\nNOT_A_NUMBER\n\n\n\n\n\n\n' | ./onboard-agent.sh ) >/dev/null 2>&1; then
    echo "should have errored on non-numeric ID"; return 1
  fi
}
assert_with_output "onboard rejects non-numeric Telegram user ID" test_onboard_rejects_non_numeric_telegram_id

# ---- pipeline integration ----
echo
echo "=== pipeline integration ==="

test_full_pipeline_idempotent() {
  local sandbox="$TMPDIR_ROOT/pipeline"
  mkdir -p "$sandbox"
  cp -r "$SCRIPT_DIR"/* "$sandbox/" 2>/dev/null
  cp "$SCRIPT_DIR/.env.example" "$sandbox/.env.local"

  ( cd "$sandbox" && printf 'Test User\nDeveloper\n123456789\nLiam\ndefault vibe\nopenai\nopenai/gpt-5\nopenai/gpt-5-mini\nOPENAI_API_KEY\n' | ./onboard-agent.sh ) >/dev/null 2>&1

  local merged_a; merged_a=$( cd "$sandbox" && ./merge-configs.sh --dry-run 2>/dev/null )
  local merged_b; merged_b=$( cd "$sandbox" && ./merge-configs.sh --dry-run 2>/dev/null )
  [[ "$merged_a" == "$merged_b" ]] || { echo "merge not idempotent after onboard"; return 1; }

  echo "$merged_a" | jq -e '.models.providers.openai.apiKey.source == "env"' >/dev/null \
    || { echo "provider config missing or wrong shape"; return 1; }
  echo "$merged_a" | jq -e '.agents.defaults.model.primary == "openai/gpt-5"' >/dev/null \
    || { echo "main model not set"; return 1; }
}
assert_with_output "full pipeline (onboard → merge) is idempotent + produces expected shape" test_full_pipeline_idempotent

# ---- known install-time TODOs ----
INSTALL_TIME_TODOS+=("Verify SecretRef shape { source, provider, id } against actual OpenClaw process startup (docs say so, not behaviorally tested)")
INSTALL_TIME_TODOS+=("Verify per-topic systemPrompt actually injects into agent context for matching chat_id+thread_id")
INSTALL_TIME_TODOS+=("Verify 'openclaw doctor' leak mitigation — re-run merge-configs.sh restores SecretRef placeholders")
INSTALL_TIME_TODOS+=("Verify clarify + status skills auto-trigger via active-memory based on description")
INSTALL_TIME_TODOS+=("Verify bootstrap budget actually fits within OpenClaw's bootstrapMaxChars at runtime")
INSTALL_TIME_TODOS+=("Verify Mission Control local install — bash install.sh --local succeeds, MC reaches OpenClaw gateway over loopback, dashboard at localhost:3000 shows live agent state")

# ---- benchmarks ----
echo
echo "=== benchmarks ==="

bench_bootstrap_chars() {
  local soul agents identity user heartbeat boot total cap
  soul=$(wc -c < "$SCRIPT_DIR/workspace/SOUL.md" | tr -d ' ')
  agents=$(wc -c < "$SCRIPT_DIR/workspace/AGENTS.md" | tr -d ' ')
  identity=$(wc -c < "$SCRIPT_DIR/workspace/IDENTITY.md.template" | tr -d ' ')
  user=$(wc -c < "$SCRIPT_DIR/workspace/USER.md.template" | tr -d ' ')
  heartbeat=$(wc -c < "$SCRIPT_DIR/workspace/HEARTBEAT.md" | tr -d ' ')
  boot=$(wc -c < "$SCRIPT_DIR/workspace/BOOT.md" 2>/dev/null | tr -d ' ')
  total=$((soul + agents + identity + user))
  cap=$(jq -r '.agents.defaults.bootstrapMaxChars // 12000' "$SCRIPT_DIR/config/00-base.json")
  printf "  bootstrap (loads once per session, system prompt):\n"
  printf "    SOUL=%d  AGENTS=%d  IDENTITY=%d  USER=%d  total=%d / cap=%d (%d%% used)\n" \
    "$soul" "$agents" "$identity" "$user" "$total" "$cap" "$((total * 100 / cap))"
  printf "  per-tick recurring loads:\n"
  printf "    HEARTBEAT=%d (×~144/day = ~%dk chars/day)\n" "$heartbeat" "$((heartbeat * 144 / 1000))"
  printf "    BOOT=%d (×~1/restart, infrequent)\n" "${boot:-0}"
}
bench_bootstrap_chars

bench_loc() {
  local total=0
  for f in "$SCRIPT_DIR"/*.sh; do
    local lines; lines=$(wc -l < "$f" | tr -d ' ')
    printf "  %-25s %5d LOC\n" "$(basename "$f")" "$lines"
    total=$((total + lines))
  done
  printf "  %-25s %5d LOC\n" "TOTAL (scripts)" "$total"
}
bench_loc

bench_skill_count() {
  local count; count=$(find "$SCRIPT_DIR/workspace/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  printf "  skills shipped: %d\n" "$count"
}
bench_skill_count

bench_config_complexity() {
  local frags merged_keys
  frags=$(ls "$SCRIPT_DIR/config"/*.json 2>/dev/null | wc -l | tr -d ' ')
  merged_keys=$( cd "$SCRIPT_DIR" && ./merge-configs.sh --dry-run 2>/dev/null | jq 'keys | length' )
  printf "  config fragments: %d (committed)\n" "$frags"
  printf "  merged top-level keys: %d\n" "$merged_keys"
}
bench_config_complexity

# ---- summary ----
echo
echo "=== results ==="
echo "passed: $PASS"
echo "failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
  echo
  echo "failures:"
  printf '  - %s\n' "${FAILURES[@]}"
fi

echo
echo "=== install-time TODOs (cannot test without OpenClaw running) ==="
printf '  • %s\n' "${INSTALL_TIME_TODOS[@]}"

[[ $FAIL -eq 0 ]] || exit 1
