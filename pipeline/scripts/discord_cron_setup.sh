#!/usr/bin/env bash
#
# discord_cron_setup.sh — one-time setup for the weekly Discord cron.
#
# 1. Stores the Discord token in macOS Keychain (prompt-only; never
#    on disk).
# 2. Symlinks the plist into ~/Library/LaunchAgents/.
# 3. Loads the agent into launchd.
#
# Re-run safe: deletes any prior keychain entry + plist link.

set -euo pipefail

REPO_ROOT="/Users/bhwilkoff/Documents/GitHub/BOBA-Playbook"
PLIST_SRC="$REPO_ROOT/pipeline/scripts/com.boba.discord-weekly.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.boba.discord-weekly.plist"

if [ ! -f "$PLIST_SRC" ]; then
  echo "FATAL: plist source not found: $PLIST_SRC"
  exit 1
fi

# ── Token in keychain ──────────────────────────────────────────────
echo "Storing Discord token in macOS Keychain (service: boba-discord-token)"
echo -n "  Paste token then press return: "
read -rs TOKEN
echo

# Replace any existing entry
security delete-generic-password -a "$USER" -s boba-discord-token >/dev/null 2>&1 || true
security add-generic-password -a "$USER" -s boba-discord-token \
    -l "BoBA Discord token (DiscordChatExporter)" \
    -w "$TOKEN"
unset TOKEN

# Verify retrievable
if security find-generic-password -a "$USER" -s boba-discord-token -w >/dev/null 2>&1; then
  echo "  ✓ token stored"
else
  echo "  ✗ failed to store token"
  exit 1
fi

# ── Install plist ──────────────────────────────────────────────────
mkdir -p "$HOME/Library/LaunchAgents"
launchctl unload "$PLIST_DST" 2>/dev/null || true
rm -f "$PLIST_DST"
cp "$PLIST_SRC" "$PLIST_DST"
launchctl load "$PLIST_DST"

# Show next-fire info
echo
echo "  ✓ plist loaded: $PLIST_DST"
echo "    next fire: Sunday 8:00 (system local time)"
echo
echo "  Manual trigger for first-run validation:"
echo "    launchctl start com.boba.discord-weekly"
echo "    tail -f ~/Library/Logs/boba-discord-weekly.log"
echo
echo "  Unload (disable cron):"
echo "    launchctl unload $PLIST_DST"
