#!/usr/bin/env bash
#
# discord_weekly_cron.sh — local-only weekly Discord pull, AUTO-only ship.
#
# Runs DCE for the last 7 days, runs evaluate_discord, ships any AUTO
# winners (score ≥ 4.5 + margin gates passed) via ship_from_eval. Near-
# miss candidates get parked under pipeline/eval/discord-weekly/<DATE>/
# for ad-hoc manual review later.
#
# Token comes from macOS Keychain (or DISCORD_TOKEN env var). Store via:
#   security add-generic-password -a "$USER" -s boba-discord-token -w "<token>"
#
# Triggered weekly by ~/Library/LaunchAgents/com.boba.discord-weekly.plist.
# Logs to ~/Library/Logs/boba-discord-weekly.log.

set -euo pipefail

# ── Paths ──────────────────────────────────────────────────────────
REPO_ROOT="/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook"
DCE_BIN="/Users/bhwilkoff/Downloads/DiscordChatExporter.Cli.osx-arm64/DiscordChatExporter.Cli"
EXPORTS_BASE="/Users/bhwilkoff/Documents/Claude/Projects/Bo Jackson Battle Arena Research/discord-weekly-exports"
EVAL_BASE="$REPO_ROOT/pipeline/eval/discord-weekly"
LOG_DIR="$HOME/Library/Logs"
LOG_FILE="$LOG_DIR/boba-discord-weekly.log"

mkdir -p "$EXPORTS_BASE" "$EVAL_BASE" "$LOG_DIR"

# Tag this run by date (Mountain Time per user_timezone memory)
RUN_TAG=$(TZ="America/Denver" date +%Y-%m-%d)
EXPORT_DIR="$EXPORTS_BASE/$RUN_TAG"
EVAL_DIR="$EVAL_BASE/$RUN_TAG"

# ── Logging helpers ────────────────────────────────────────────────
log() {
  local ts; ts=$(TZ="America/Denver" date +"%Y-%m-%d %H:%M:%S MT")
  echo "[$ts] $*" | tee -a "$LOG_FILE"
}
log "═══ Discord weekly run start ($RUN_TAG) ═══"

# ── Resolve token ──────────────────────────────────────────────────
if [ -n "${DISCORD_TOKEN:-}" ]; then
  TOKEN="$DISCORD_TOKEN"
else
  TOKEN=$(security find-generic-password -a "$USER" -s boba-discord-token -w 2>/dev/null || true)
fi
if [ -z "${TOKEN:-}" ]; then
  log "FATAL: no Discord token (DISCORD_TOKEN env or keychain 'boba-discord-token')"
  exit 1
fi

# ── Date range: last 7 days ────────────────────────────────────────
AFTER=$(TZ="America/Denver" date -v-7d +%Y-%m-%d)
BEFORE=$(TZ="America/Denver" date +%Y-%m-%d)
log "DCE range: $AFTER → $BEFORE"

mkdir -p "$EXPORT_DIR"

# ── Run DCE (JSON-only, then parallel media download) ─────────────
# Two-phase pattern: DCE writes the JSON fast (seconds), then a paralleled
# downloader (4 workers) pulls media ~4× faster than DCE's sequential
# --media. Safe: Discord CDN URLs don't use the token, so parallel CDN
# requests cannot get the token banned. Channels: general, feedback-and-
# support, trade-room.
# NOTE: DCE channels run SEQUENTIALLY (no --parallel). DCE's --parallel
# flag runs N channels in parallel, each hammering Discord's API with
# the user's token. --parallel 3 triggered a token-level rate limit on
# 2026-05-08 that blocked Ben's desktop Discord too. Don't reintroduce.
log "DCE export start (JSON-only, sequential channels)"
if "$DCE_BIN" export \
    -t "$TOKEN" \
    -c 1305710603440095255 1448759509076934778 1306146115757936650 \
    -f Json \
    --after "$AFTER" \
    --before "$BEFORE" \
    -o "$EXPORT_DIR/%C.json" >> "$LOG_FILE" 2>&1
then
  log "DCE JSON export OK"
else
  log "FATAL: DCE failed (see log above)"
  exit 1
fi

log "media download start (4 parallel workers)"
if python3 "$REPO_ROOT/pipeline/scripts/download_discord_media.py" \
    --exports-dir "$EXPORT_DIR" \
    --workers 4 >> "$LOG_FILE" 2>&1
then
  log "media download OK"
else
  log "WARN: media download exited non-zero (see log)"
fi

# ── Evaluate ───────────────────────────────────────────────────────
log "evaluate_discord start"
cd "$REPO_ROOT"
mkdir -p "$EVAL_DIR"
if python3 pipeline/scripts/evaluate_discord.py \
    --exports-dir "$EXPORT_DIR" \
    --output-dir  "$EVAL_DIR" >> "$LOG_FILE" 2>&1
then
  log "evaluate OK"
else
  log "WARN: evaluate exited non-zero (see log)"
fi

# Surface counts
N_AUTO=$(python3 -c "import json,sys; sys.exit(0)
import json; print(len(json.load(open('$EVAL_DIR/winners.json'))))" 2>/dev/null || echo "?")
log "AUTO winners: $N_AUTO"

# ── Ship AUTO winners ──────────────────────────────────────────────
# Empty excludes file = approve everything that passed AUTO gates.
EMPTY_EXCLUDES=$(mktemp)
if [ "$N_AUTO" != "?" ] && [ "$N_AUTO" -gt 0 ]; then
  log "ship_from_eval start"
  if python3 pipeline/scripts/ship_from_eval.py \
      --eval-dir "$EVAL_DIR" \
      --excludes-file "$EMPTY_EXCLUDES" >> "$LOG_FILE" 2>&1
  then
    log "ship OK — see PR in log"
  else
    log "WARN: ship exited non-zero (see log)"
  fi
else
  log "no AUTO winners — skipping ship"
fi
rm -f "$EMPTY_EXCLUDES"

# ── Near-miss review surface ───────────────────────────────────────
# Generate the manual-sweep HTML so user can review at their leisure.
if [ -f "$EVAL_DIR/output.jsonl" ]; then
  python3 pipeline/scripts/near_miss_review.py \
      --eval-dir "$EVAL_DIR" >> "$LOG_FILE" 2>&1 || true
fi

# ── Cleanup media ──────────────────────────────────────────────────
log "cleanup media"
freed=0
for d in "$EXPORT_DIR"/*_Files; do
  [ -d "$d" ] || continue
  size=$(du -sk "$d" 2>/dev/null | awk '{print $1}')
  rm -rf "$d"
  freed=$((freed + size))
done
log "freed $((freed/1024)) MB"

# Trim heavy eval intermediates (keep crops/, winners, report)
rm -f "$EVAL_DIR/output.jsonl" "$EVAL_DIR/input.jsonl"

log "═══ Discord weekly run done ($RUN_TAG) ═══"
