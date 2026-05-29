#!/bin/zsh
# daily_pricing_refresh.sh — orchestrate the daily self-improving pricing
# loop on a local Mac via launchd. Uses Ben's existing wrangler OAuth
# token (cached locally) + macOS Keychain git credentials. No new
# secrets, no GitHub Actions, no Cloudflare API tokens.
#
# Loop (full architecture in PRICING_AUTOMATION.md):
#   refresh stale prices  →  rebuild estimator artifact  →
#     audit  →  track history  →  check regressions  →
#       calibrate  →  commit + push if clean
#
# A regression aborts the commit but preserves the rebuilt artifact
# locally for inspection. macOS notification fires on regression.
#
# Logs to ~/Library/Logs/boba-pricing-daily.{out,err}.log via the
# launchd plist (scripts/com.bobaplaybook.pricing-daily.plist).
#
# Usage:
#   scripts/daily_pricing_refresh.sh                 # full daily run
#   scripts/daily_pricing_refresh.sh --skip-refresh  # rebuild only
#   scripts/daily_pricing_refresh.sh --dry           # everything except commit/push

set -u
set -o pipefail

# Per-step failures are reported in the summary but don't abort the run
# until we get to the regression gate. The refresh steps are
# best-effort — eBay quota exhaustion shouldn't stop the rebuild.

EBAY_STALE_LIMIT="${EBAY_STALE_LIMIT:-800}"
WHATNOT_STALE_LIMIT="${WHATNOT_STALE_LIMIT:-400}"
CRAWL_NEW_LIMIT="${CRAWL_NEW_LIMIT:-400}"
DRY_RUN=0
SKIP_REFRESH=0

for arg in "$@"; do
  case "$arg" in
    --dry)          DRY_RUN=1 ;;
    --skip-refresh) SKIP_REFRESH=1 ;;
    --help|-h)
      sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown flag: $arg" >&2; exit 64 ;;
  esac
done

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO" || { echo "FATAL: cannot cd to $REPO" >&2; exit 1; }

# Ensure PATH includes homebrew binaries — launchd starts with a
# minimal PATH that excludes Apple-Silicon's /opt/homebrew.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

TS="$(date +%Y-%m-%dT%H:%M:%S)"
echo ""
echo "========================================================================"
echo "$TS — BOBA daily pricing refresh"
echo "  repo:       $REPO"
echo "  dry-run:    $DRY_RUN"
echo "  skip-refresh: $SKIP_REFRESH"
echo "  limits:     ebay-stale=$EBAY_STALE_LIMIT whatnot-stale=$WHATNOT_STALE_LIMIT crawl-new=$CRAWL_NEW_LIMIT"
echo "========================================================================"

notify() {
  # macOS notification — visible even when run from launchd. Title +
  # message + sound. Subtitle gives a quick-glance hint at the cause.
  local title="$1" message="$2" subtitle="${3:-}"
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$message\" with title \"$title\" subtitle \"$subtitle\" sound name \"Glass\"" 2>/dev/null || true
  fi
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FATAL: required command '$1' not found in PATH" >&2
    notify "BOBA pricing daily — FAILED" "Required command '$1' not found." "Check the .zshrc PATH or launchd plist."
    exit 127
  fi
}
require python3
require git
require npx     # for wrangler
require curl

# Verify wrangler is authenticated. With launchd we inherit the user's
# wrangler config from ~/Library/Preferences/.wrangler-config (or
# ~/.config/.wrangler/config). If it isn't there, the build step will
# fail later with a less-friendly error — pre-flight is friendlier.
echo "→ Verifying wrangler auth…"
if ! npx wrangler whoami 2>&1 | grep -q "logged in"; then
  echo "FATAL: wrangler is not logged in. Run 'npx wrangler login' from this user account, then re-run." >&2
  notify "BOBA pricing daily — FAILED" "wrangler not authenticated." "Run 'npx wrangler login' once, then re-enable cron."
  exit 1
fi

# Stay in sync with origin so we don't commit on a stale tree.
# --autostash handles the case where a previous run left the artifact
# files dirty (e.g., manual `audit_estimator.py` between cron runs).
echo "→ git pull --rebase --autostash…"
if ! git pull --rebase --autostash origin main; then
  echo "FATAL: git pull failed — fix conflicts, then re-run." >&2
  notify "BOBA pricing daily — FAILED" "git pull failed." "Resolve conflicts and re-run."
  exit 1
fi

# ── 1/2/3. Refresh stale + seed new (best-effort) ────────────────────
if (( SKIP_REFRESH == 0 )); then
  echo "→ refresh_stale_prices.py --source ebay --limit $EBAY_STALE_LIMIT"
  python3 scripts/refresh_stale_prices.py --source ebay \
    --stale-days 14 --limit "$EBAY_STALE_LIMIT" --delay 1.5 \
    || echo "  ⚠ eBay refresh failed/quota — continuing"

  echo "→ refresh_stale_prices.py --source whatnot --limit $WHATNOT_STALE_LIMIT"
  python3 scripts/refresh_stale_prices.py --source whatnot \
    --stale-days 7 --limit "$WHATNOT_STALE_LIMIT" --delay 0.8 \
    || echo "  ⚠ Whatnot refresh failed — continuing"

  echo "→ crawl_active_listings.py --limit $CRAWL_NEW_LIMIT"
  python3 scripts/crawl_active_listings.py --source ebay \
    --limit "$CRAWL_NEW_LIMIT" --delay 1.5 \
    || echo "  ⚠ catalog crawl failed/quota — continuing"
else
  echo "→ skip-refresh: skipping refresh + crawl steps"
fi

# ── 4. Rebuild artifact ──────────────────────────────────────────────
echo "→ build_price_estimates.py"
if ! python3 scripts/build_price_estimates.py | tee /tmp/boba-pricing-build.log; then
  echo "FATAL: build_price_estimates.py failed — see log above" >&2
  notify "BOBA pricing daily — FAILED" "build_price_estimates.py failed." "Check ~/Library/Logs/boba-pricing-daily.err.log"
  exit 1
fi

# ── 5. Audit ─────────────────────────────────────────────────────────
echo "→ audit_estimator.py"
python3 scripts/audit_estimator.py | tee /tmp/boba-pricing-audit.log

# ── 6. Track history ─────────────────────────────────────────────────
echo "→ track_audit_history.py"
python3 scripts/track_audit_history.py

# ── 7. Regression gate — DO NOT COMMIT if critical regression ────────
echo "→ check_audit_regressions.py"
if ! python3 scripts/check_audit_regressions.py 2>&1 | tee /tmp/boba-pricing-regress.log; then
  REGRESS_HEAD=$(grep "CRITICAL" /tmp/boba-pricing-regress.log | head -3 || true)
  echo ""
  echo "❌ CRITICAL REGRESSION — artifact NOT committed."
  echo "$REGRESS_HEAD"
  notify "BOBA pricing daily — REGRESSION" \
    "Critical regression — artifact not committed." \
    "$(echo "$REGRESS_HEAD" | head -1)"
  # Don't exit fatally; we want calibration to still run + logs to flush.
  REGRESSION=1
else
  REGRESSION=0
fi

# ── 8. Calibration recommendations (advisory) ────────────────────────
echo "→ calibrate_estimator.py --window-days 14"
python3 scripts/calibrate_estimator.py --window-days 14 || true

# ── 9. Commit + push if clean ────────────────────────────────────────
if (( REGRESSION == 1 )); then
  echo ""
  echo "Skipping commit due to regression. Inspect:"
  echo "  /tmp/boba-pricing-regress.log"
  echo "  assets/data/price-estimates-audit.json"
  echo "  assets/data/pricing-audit-history.json (last row)"
  echo "Resolve, then re-run: scripts/daily_pricing_refresh.sh --skip-refresh"
  exit 1
fi

if (( DRY_RUN == 1 )); then
  echo "→ --dry: skipping commit + push"
  exit 0
fi

# Stage just the pricing artifacts (don't sweep unrelated edits).
git add assets/data/price-estimates.json \
        assets/data/price-estimates-audit.json \
        assets/data/pricing-audit-history.json \
        assets/data/pricing-calibration-recommendations.json

if git diff --cached --quiet; then
  echo "→ no artifact changes today (D1 tracker data didn't shift)"
  exit 0
fi

# Headlines from the build + audit logs for the commit message.
COVERAGE=$(grep -oE 'estimates produced: [0-9]+ / [0-9]+ cards \([0-9]+% coverage\)' /tmp/boba-pricing-build.log | tail -1 || echo "(coverage unknown)")
FLAGGED=$(grep -oE '[0-9]+ cards flagged by 2\+ audits' /tmp/boba-pricing-audit.log | tail -1 || echo "0 cards flagged")
DATE=$(date -u +%Y-%m-%d)

git commit -m "pricing: daily refresh — $DATE [skip ci]

$COVERAGE
$FLAGGED

Triggered by local launchd cron (scripts/daily_pricing_refresh.sh).
See PRICING_AUTOMATION.md for the loop architecture."

echo "→ git push origin main"
git push origin main

notify "BOBA pricing daily — OK" \
  "$COVERAGE · $FLAGGED" \
  "Artifact committed + pushed."
echo ""
echo "✓ Daily refresh complete."
