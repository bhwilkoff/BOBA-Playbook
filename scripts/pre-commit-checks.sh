#!/usr/bin/env bash
# scripts/pre-commit-checks.sh — repo-level pre-commit guard.
#
# Installed via:
#     git config core.hooksPath .githooks
# (see .githooks/pre-commit which calls this)
#
# Runs the two side-channel maintenance tasks that have bitten us
# repeatedly in the past week:
#
#   1. iOS Card.swift / ScanMatching.swift → CLI Mirror sync
#      (Stage B pipeline gates on byte-identity, fails nightly when
#       drift is allowed to land — Mirror/Card.swift broke on
#       2026-05-26 from this week's bobaId v3 changes).
#
#   2. bobaId v3 invariant audit across every catalog bundle +
#      every derived data file. Catches the "side-channel file no
#      script maintains" class of regression that hid the empty-
#      Collection bug for two debugging cycles (cards-slim.json
#      stale → Android APK shipped 17,915 v2-bobaId cards while
#      Supabase had 17,974 v3 — bug Ben hit on 2026-05-25).
#
# Both checks are FAST (audit reads 5 bundles + 6 derived files in
# under a second; mirror sync is a diff + cp of 2 files). If either
# fails, the commit is blocked with a clear remediation hint.
#
# Bypass: `git commit --no-verify` (use sparingly — these guards
# exist because the failures they catch are silent and expensive).

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

echo "─ Running pre-commit checks (mirror sync + bobaId v3 audit)…"

# ─── 1. iOS → CLI Mirror sync ─────────────────────────────────
# If the iOS source files changed in this commit, sync them into
# the CLI Mirror directory + auto-stage the mirror updates. That
# way the commit always includes a fresh mirror.
ios_sources_in_commit=$(git diff --cached --name-only \
    -- BOBAPlaybook/Models/Card.swift BOBAPlaybook/Views/Scan/ScanMatching.swift \
    2>/dev/null | wc -l | tr -d ' ')

if [ "$ios_sources_in_commit" -gt 0 ]; then
    echo "  ▸ iOS source files staged — syncing CLI Mirror…"
    pipeline/recognition/sync_mirror.sh
    git add pipeline/recognition/CardRecognitionCLI/Sources/CardRecognitionCLI/Mirror/
fi

# Regardless of what's staged, verify no drift exists. Catches the
# case where someone edited the Mirror directly + forgot to mirror
# back, OR where a prior commit landed without running the hook.
if ! diff -q BOBAPlaybook/Models/Card.swift \
    pipeline/recognition/CardRecognitionCLI/Sources/CardRecognitionCLI/Mirror/Card.swift \
    > /dev/null 2>&1; then
    echo "  ✗ Mirror/Card.swift drift detected."
    echo "    Run: pipeline/recognition/sync_mirror.sh"
    exit 1
fi
if ! diff -q BOBAPlaybook/Views/Scan/ScanMatching.swift \
    pipeline/recognition/CardRecognitionCLI/Sources/CardRecognitionCLI/Mirror/ScanMatching.swift \
    > /dev/null 2>&1; then
    echo "  ✗ Mirror/ScanMatching.swift drift detected."
    echo "    Run: pipeline/recognition/sync_mirror.sh"
    exit 1
fi
echo "  ✓ Mirror in sync with iOS sources"

# ─── 2. bobaId v3 audit ──────────────────────────────────────
# Only run when a catalog bundle or derived data file is staged —
# the audit takes ~1s but reads ~30 MB of JSON. Skip when the
# commit is purely non-data (e.g. a doc-only fix).
data_in_commit=$(git diff --cached --name-only \
    -- 'assets/data/*.json' \
       'BOBAPlaybook/*.json' \
       'android/app/src/main/assets/**/*.json' \
       'pipeline/scripts/regen_bundles.py' \
       'pipeline/scripts/apply_audit_patch.py' \
       'scripts/boba_id.py' \
    2>/dev/null | wc -l | tr -d ' ')

if [ "$data_in_commit" -gt 0 ]; then
    echo "  ▸ Catalog data staged — running bobaId v3 audit…"
    if python3 pipeline/scripts/audit_bobaid_v3.py > /tmp/audit-output.log 2>&1; then
        echo "  ✓ bobaId v3 audit clean"
    else
        echo "  ✗ bobaId v3 audit failed. Output:"
        cat /tmp/audit-output.log | sed 's/^/    /'
        echo
        echo "    Fix: run \`python3 pipeline/scripts/regen_bundles.py\`"
        echo "         then re-stage + commit."
        exit 1
    fi
fi

echo "─ Pre-commit checks passed."
