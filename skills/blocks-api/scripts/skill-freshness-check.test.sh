#!/usr/bin/env bash
# Tests for skill-freshness-check.sh.
#
# Copies the skill into a throwaway project layout (<tmp>/.agents/skills/
# blocks-api) so the script resolves its scope root the same way it does after
# a real `npx skills add`, then drives it with a fake clock and a fake update
# command. Run with: bash skills/blocks-api/scripts/skill-freshness-check.test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd -P)
skill_src=$(cd "$here/.." && pwd -P)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export XDG_CACHE_HOME="$tmp/cache"
export HOME="$tmp/home"
mkdir -p "$HOME"
unset BLOCKS_SKILLS_NO_UPDATE BLOCKS_SKILLS_DEBUG BLOCKS_SKILLS_ROOT

root="$tmp/project"
skill_dir="$root/.agents/skills/blocks-api"
mkdir -p "$root/.agents/skills"
cp -R "$skill_src" "$skill_dir"
script="$skill_dir/scripts/skill-freshness-check.sh"

# The fake update command records each invocation and acts on a mode file:
#   ok       print an "up to date" message, exit 0
#   change   append to SKILL.md so the fingerprint changes, exit 0
#   fail     print the CLI's failure wording, exit 0 (as the real CLI does)
#   exit1    exit non-zero without saying anything
#   missing  print the CLI's "not installed" message, exit 0
#   hang     spawn a long sleep (pid written to $hung_pid) and wait on it
calls="$tmp/calls"
mode="$tmp/mode"
hung_pid="$tmp/hung-pid"
fake="$tmp/fake-update.sh"
cat > "$fake" <<FAKE
#!/bin/sh
echo "\$(pwd -P)" >> "$calls"
case \$(cat "$mode") in
  ok)      echo "✓ All global skills are up to date" ;;
  change)  echo "  ✓ Updated blocks-api"; echo "# changed" >> "$skill_dir/SKILL.md" ;;
  fail)    echo "  ✗ Failed to check skills from BlocksOrg/skills" ;;
  exit1)   exit 1 ;;
  missing) echo "No installed skills found matching: blocks-api" ;;
  hang)    sleep 300 & echo \$! > "$hung_pid"; wait ;;
esac
exit 0
FAKE
chmod +x "$fake"
export BLOCKS_SKILLS_UPDATE_CMD="$fake"

T0=1700000000
MIN=60
HOUR=3600

pass=0
fail=0
fail_msgs=""

run() { # run <now> -> sets $out and $rc
  out=$(BLOCKS_SKILLS_NOW=$1 bash "$script" 2>"$tmp/stderr")
  rc=$?
}

not_running() { ! kill -0 "$1" 2>/dev/null; }

call_count() {
  if [ -f "$calls" ]; then wc -l < "$calls" | tr -d ' '; else echo 0; fi
}

reset() {
  rm -rf "$XDG_CACHE_HOME" "$calls"
  echo ok > "$mode"
}

check() { # check <description> <condition...>
  desc=$1; shift
  if "$@"; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    fail_msgs="$fail_msgs
  ✗ $desc"
    echo "FAIL: $desc" >&2
  fi
}

# --- first run updates, second run within 24h does not --------------------------
reset
run $T0
check "first run exits 0" [ "$rc" -eq 0 ]
check "first run invokes the update command" [ "$(call_count)" -eq 1 ]
check "first run is silent when nothing changed" [ -z "$out" ]
check "update runs from the scope root" [ "$(head -n1 "$calls")" = "$(cd "$root" && pwd -P)" ]

run $((T0 + 1 * HOUR))
check "second run within 24h exits 0" [ "$rc" -eq 0 ]
check "second run within 24h skips the update" [ "$(call_count)" -eq 1 ]

run $((T0 + 23 * HOUR))
check "run at 23h still skips" [ "$(call_count)" -eq 1 ]

run $((T0 + 25 * HOUR))
check "run after 24h updates again" [ "$(call_count)" -eq 2 ]

# --- a real change prints exactly one note ---------------------------------------
reset
echo change > "$mode"
run $T0
check "changed files exit 0" [ "$rc" -eq 0 ]
check "changed files print a one-line note" [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ]
case $out in
  *"blocks-api skill was refreshed"*) check "note names the skill" true ;;
  *) check "note names the skill" false ;;
esac
echo ok > "$mode"
run $((T0 + 1 * HOUR))
check "no note on the throttled run that follows" [ -z "$out" ]

# --- failures retry after 15 minutes, then back off to daily ---------------------
reset
echo fail > "$mode"
run $T0                                   # failure 1
check "failure exits 0" [ "$rc" -eq 0 ]
check "failure prints nothing" [ -z "$out" ]
check "failure 1 recorded" [ "$(call_count)" -eq 1 ]

run $((T0 + 5 * MIN))
check "no retry 5 minutes after a failure" [ "$(call_count)" -eq 1 ]

run $((T0 + 16 * MIN))                    # failure 2
check "retry 16 minutes after a failure" [ "$(call_count)" -eq 2 ]

run $((T0 + 32 * MIN))                    # failure 3
check "third attempt after another 16 minutes" [ "$(call_count)" -eq 3 ]

run $((T0 + 48 * MIN))
check "after 3 failures, no retry 16 minutes later" [ "$(call_count)" -eq 3 ]

run $((T0 + 32 * MIN + 23 * HOUR))
check "after 3 failures, still no retry at 23h" [ "$(call_count)" -eq 3 ]

echo ok > "$mode"
run $((T0 + 32 * MIN + 25 * HOUR))        # success resets the counter
check "after 3 failures, retries once a day" [ "$(call_count)" -eq 4 ]

echo fail > "$mode"
run $((T0 + 32 * MIN + 50 * HOUR))        # failure 1 again
run $((T0 + 32 * MIN + 50 * HOUR + 16 * MIN))
check "a success resets the failure counter (15m retry again)" [ "$(call_count)" -eq 6 ]

# --- non-zero exit from the update command counts as a failure ------------------
reset
echo exit1 > "$mode"
run $T0
check "non-zero update exit still exits 0" [ "$rc" -eq 0 ]
run $((T0 + 16 * MIN))
check "non-zero update exit is retried after 15 minutes" [ "$(call_count)" -eq 2 ]

# --- 'not installed' is not a failure; check again tomorrow, not in 15 minutes ----
reset
echo missing > "$mode"
run $T0
check "untracked install exits 0" [ "$rc" -eq 0 ]
check "untracked install prints nothing" [ -z "$out" ]
run $((T0 + 16 * MIN))
check "untracked install is not retried after 15 minutes" [ "$(call_count)" -eq 1 ]

# --- a stalled update is killed at the deadline and counted as a failure ---------
reset
echo hang > "$mode"
started=$(date +%s)
BLOCKS_SKILLS_TIMEOUT=2 run $T0
elapsed=$(( $(date +%s) - started ))
check "stalled update exits 0" [ "$rc" -eq 0 ]
check "stalled update prints nothing" [ -z "$out" ]
check "stalled update returns within the deadline (took ${elapsed}s)" [ "$elapsed" -le 10 ]
check "stalled update's whole process tree is killed" not_running "$(cat "$hung_pid")"
run $((T0 + 5 * MIN))
check "stalled update counts as a failure (no retry at 5m)" [ "$(call_count)" -eq 1 ]
echo ok > "$mode"
run $((T0 + 16 * MIN))
check "stalled update is retried after 15 minutes" [ "$(call_count)" -eq 2 ]

# --- opt-out --------------------------------------------------------------------
reset
BLOCKS_SKILLS_NO_UPDATE=1 run $T0
check "opt-out exits 0" [ "$rc" -eq 0 ]
check "opt-out prints nothing" [ -z "$out" ]
check "opt-out never invokes the update command" [ "$(call_count)" -eq 0 ]

# --- a missing update command can never break the caller ------------------------
reset
BLOCKS_SKILLS_UPDATE_CMD="$tmp/does-not-exist" run $T0
check "missing update command exits 0" [ "$rc" -eq 0 ]
check "missing update command prints nothing" [ -z "$out" ]

# --- an unwritable cache dir is skipped quietly ---------------------------------
reset
bad_cache="$tmp/not-a-dir"
touch "$bad_cache"
XDG_CACHE_HOME="$bad_cache" run $T0
check "unwritable cache exits 0" [ "$rc" -eq 0 ]
check "unwritable cache skips the update" [ "$(call_count)" -eq 0 ]

# --- debug logging goes to stderr only ------------------------------------------
reset
out=$(BLOCKS_SKILLS_NOW=$T0 BLOCKS_SKILLS_DEBUG=1 bash "$script" 2>"$tmp/stderr")
check "debug keeps stdout clean" [ -z "$out" ]
check "debug logs the decision to stderr" grep -q 'scope root' "$tmp/stderr"

echo
echo "$pass passed, $fail failed"
if [ "$fail" -ne 0 ]; then
  echo "$fail_msgs"
  exit 1
fi
