#!/bin/zsh
# install_pricing_cron.sh — one-shot installer for the daily pricing
# refresh launchd job. Symlinks the repo plist into LaunchAgents and
# loads it with launchctl. Idempotent — safe to re-run.
#
# Usage:
#   scripts/install_pricing_cron.sh           # install + load
#   scripts/install_pricing_cron.sh --uninstall  # unload + remove symlink
#   scripts/install_pricing_cron.sh --trigger    # fire the job now (test)
#
# See PRICING_AUTOMATION.md §7 for the full setup story.

set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_REPO="$REPO/scripts/com.bobaplaybook.pricing-daily.plist"
PLIST_LINK="$HOME/Library/LaunchAgents/com.bobaplaybook.pricing-daily.plist"
LABEL="com.bobaplaybook.pricing-daily"
DOMAIN="gui/$(id -u)"

case "${1:-install}" in
  install)
    [[ -f "$PLIST_REPO" ]] || { echo "FATAL: plist not found at $PLIST_REPO" >&2; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    mkdir -p "$HOME/Library/Logs"
    ln -sfn "$PLIST_REPO" "$PLIST_LINK"
    echo "→ symlinked $PLIST_LINK"
    # bootout first (idempotent) so we re-load the latest plist content.
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    launchctl bootstrap "$DOMAIN" "$PLIST_LINK"
    launchctl enable "$DOMAIN/$LABEL"
    echo "→ bootstrapped + enabled $LABEL in $DOMAIN"
    echo ""
    echo "Next steps:"
    echo "  - Verify wrangler is logged in: npx wrangler whoami"
    echo "  - Test the script: scripts/install_pricing_cron.sh --trigger"
    echo "  - Watch logs: tail -f ~/Library/Logs/boba-pricing-daily.out.log"
    echo "  - Cron fires daily at 09:00 local. To change, edit the plist's"
    echo "    StartCalendarInterval block + re-run this installer."
    ;;
  --uninstall|uninstall)
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST_LINK"
    echo "→ unloaded + removed $PLIST_LINK"
    echo "  (the repo file at $PLIST_REPO is untouched)"
    ;;
  --trigger|trigger)
    launchctl kickstart -p "$DOMAIN/$LABEL"
    echo "→ triggered $LABEL — watch ~/Library/Logs/boba-pricing-daily.out.log"
    ;;
  --status|status)
    launchctl print "$DOMAIN/$LABEL" 2>&1 | head -30
    ;;
  *)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 64
    ;;
esac
