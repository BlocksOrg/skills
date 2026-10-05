#!/usr/bin/env bash
# Keep the installed blocks-api skill fresh without getting in the agent's way.
#
# The agent runs this once per invocation of the skill. The script decides
# whether an update is due, runs `npx skills update` from the right directory,
# and reports a single line on stdout only when the skill files actually
# changed. It never fails: every path exits 0, so a broken network or a
# missing npx can never block the task the agent was asked to do.
#
# Throttling (per scope root, tracked in a small marker file):
#   - after a successful check, stay quiet for 24 hours
#   - after a failed check, retry 15 minutes later
#   - after 3 consecutive failures, back off to one attempt per day
#
# Environment:
#   BLOCKS_SKILLS_NO_UPDATE=1   opt out entirely (exit 0 immediately)
#   BLOCKS_SKILLS_DEBUG=1       log every decision to stderr
#   BLOCKS_SKILLS_NOW           override the clock (epoch seconds), for tests
#   BLOCKS_SKILLS_UPDATE_CMD    override the update command, for tests
#   BLOCKS_SKILLS_ROOT          override the detected scope root, for tests
#   XDG_CACHE_HOME              marker files live under $XDG_CACHE_HOME/blocks-skills
#                               (defaults to ~/.cache)

SKILL_NAME="blocks-api"
SKILLS_CLI_VERSION="1.7.0"

SUCCESS_INTERVAL=86400   # 24h: do not re-check after a success
RETRY_INTERVAL=900       # 15m: retry after a failure
MAX_FAILURES=3           # after this many failures in a row, retry daily
UPDATE_TIMEOUT=120       # seconds; only enforced where `timeout` exists

log() {
  if [ -n "${BLOCKS_SKILLS_DEBUG:-}" ]; then
    printf 'skill-freshness-check: %s\n' "$*" >&2
  fi
}

if [ -n "${BLOCKS_SKILLS_NO_UPDATE:-}" ]; then
  log "BLOCKS_SKILLS_NO_UPDATE is set; skipping"
  exit 0
fi

# --- locate ourselves ---------------------------------------------------------
# `pwd -P` resolves symlinks, so being invoked through ~/.claude/skills/<name>
# still lands on the real ~/.agents/skills/<name> directory.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd -P) || exit 0
skill_dir=$(cd "$script_dir/.." 2>/dev/null && pwd -P) || exit 0

# The skills CLI reads project locks from the current directory and global
# locks from the home directory. Walk up from the skill until we hit the
# directory that owns the `.agents/` (or `.claude/`) tree; that is where
# `npx skills update` must run so both scopes are considered.
find_root() {
  dir=$skill_dir
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    dir=$(dirname "$dir")
    if [ -d "$dir/.agents" ] || [ -d "$dir/.claude" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  return 1
}

if [ -n "${BLOCKS_SKILLS_ROOT:-}" ]; then
  root=$BLOCKS_SKILLS_ROOT
elif ! root=$(find_root); then
  root=${HOME:-}
fi
if [ -z "$root" ] || [ ! -d "$root" ]; then
  log "could not determine a scope root; skipping"
  exit 0
fi
log "skill dir: $skill_dir"
log "scope root: $root"

# --- marker file --------------------------------------------------------------
cache_home=${XDG_CACHE_HOME:-${HOME:-}/.cache}
if [ -z "${XDG_CACHE_HOME:-}" ] && [ -z "${HOME:-}" ]; then
  log "neither XDG_CACHE_HOME nor HOME is set; skipping"
  exit 0
fi
root_hash=$(printf '%s' "$root" | cksum | cut -d' ' -f1)
marker_dir="$cache_home/blocks-skills/$root_hash"
marker="$marker_dir/$SKILL_NAME"
if ! mkdir -p "$marker_dir" 2>/dev/null; then
  log "cannot create $marker_dir; skipping"
  exit 0
fi

now=${BLOCKS_SKILLS_NOW:-$(date +%s)}
case $now in
  ''|*[!0-9]*) log "invalid clock value '$now'; skipping"; exit 0 ;;
esac

last_success=0
last_attempt=0
failures=0
if [ -f "$marker" ]; then
  while IFS='=' read -r key value; do
    case $value in ''|*[!0-9]*) continue ;; esac
    case $key in
      last_success) last_success=$value ;;
      last_attempt) last_attempt=$value ;;
      failures)     failures=$value ;;
    esac
  done < "$marker"
fi
log "marker: $marker (last_success=$last_success last_attempt=$last_attempt failures=$failures)"

write_marker() {
  tmp="$marker.$$.tmp"
  {
    printf 'last_success=%s\n' "$last_success"
    printf 'last_attempt=%s\n' "$last_attempt"
    printf 'failures=%s\n' "$failures"
  } > "$tmp" 2>/dev/null && mv -f "$tmp" "$marker" 2>/dev/null
  rm -f "$tmp" 2>/dev/null
}

# --- is an update due? --------------------------------------------------------
if [ $((now - last_success)) -lt $SUCCESS_INTERVAL ]; then
  log "checked successfully $((now - last_success))s ago; not due"
  exit 0
fi

backoff=$RETRY_INTERVAL
if [ "$failures" -ge $MAX_FAILURES ]; then
  backoff=$SUCCESS_INTERVAL
fi
if [ $((now - last_attempt)) -lt $backoff ]; then
  log "last attempt was $((now - last_attempt))s ago (backoff ${backoff}s, failures=$failures); not due"
  exit 0
fi

# --- run the update -----------------------------------------------------------
fingerprint() {
  (
    cd "$skill_dir" 2>/dev/null || exit 0
    for f in SKILL.md references/*.md scripts/*.sh; do
      [ -f "$f" ] && cksum "$f"
    done | cksum
  )
}

update_cmd=${BLOCKS_SKILLS_UPDATE_CMD:-"npx --yes skills@$SKILLS_CLI_VERSION update $SKILL_NAME -y"}
if [ -z "${BLOCKS_SKILLS_UPDATE_CMD:-}" ] && ! command -v npx >/dev/null 2>&1; then
  log "npx not found on PATH; skipping"
  exit 0
fi

runner=""
if command -v timeout >/dev/null 2>&1; then
  runner="timeout $UPDATE_TIMEOUT"
fi

last_attempt=$now
write_marker

before=$(fingerprint)
log "running: $update_cmd (in $root)"
# shellcheck disable=SC2086  # $runner is intentionally word-split
output=$(cd "$root" && $runner sh -c "$update_cmd" 2>&1 </dev/null)
rc=$?
after=$(fingerprint)
log "update exit code: $rc"
if [ -n "${BLOCKS_SKILLS_DEBUG:-}" ]; then
  esc=$(printf '\033')
  printf '%s\n' "$output" | sed "s/$esc\[[0-9;?]*[a-zA-Z]//g; s/^/skill-freshness-check: | /" >&2
fi

# The CLI exits 0 for most of its own error paths, so look at the output too.
failed=0
if [ "$rc" -ne 0 ]; then
  failed=1
elif printf '%s\n' "$output" | grep -qiE 'failed|cannot update|npm err|error'; then
  failed=1
fi

if [ "$failed" -eq 1 ]; then
  failures=$((failures + 1))
  write_marker
  log "update failed (failures=$failures)"
  exit 0
fi

last_success=$now
failures=0
write_marker

if [ "$before" != "$after" ]; then
  log "skill files changed"
  printf 'Note: the %s skill was refreshed to the latest published version. The updated instructions take effect in your next session.\n' "$SKILL_NAME"
else
  log "skill already up to date"
fi
exit 0
