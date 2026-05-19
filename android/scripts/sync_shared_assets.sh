#!/usr/bin/env bash
# android/scripts/sync_shared_assets.sh
#
# Copy shared assets (card catalog JSON + brand fonts) from the
# monorepo root into the Android app target.
#
# Modes:
#   ./sync_shared_assets.sh            update destination
#   ./sync_shared_assets.sh --check    fail-on-drift; CI uses this
#
# Same shape as pipeline/recognition/sync_mirror.sh — single source of
# truth (the repo root), Android consumes a copy.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC_DATA="${REPO_ROOT}/assets/data"
SRC_FONTS="${REPO_ROOT}/BOBAPlaybook/Resources/Fonts"
DEST_ASSETS="${REPO_ROOT}/android/app/src/main/assets/data"
DEST_FONTS="${REPO_ROOT}/android/app/src/main/res/font"

mode="${1:-update}"

mkdir -p "${DEST_ASSETS}" "${DEST_FONTS}"

# (source_file destination_file)
#
# We bundle the SLIM catalog (cards-slim.json @ ~13 MB), not the
# full web catalog (~18 MB) or the giant search-index.json (~23 MB).
# Android generates its own search index at first launch — same
# pattern iOS uses (the on-device index is built per-platform on
# install). This trims ~28 MB off the APK without losing any
# functionality.
SHARED_FILES=(
    "${SRC_DATA}/cards-slim.json     ${DEST_ASSETS}/cards.json"
    "${SRC_DATA}/categories.json     ${DEST_ASSETS}/categories.json"
)

# Fonts — copy AND rename to Android's required snake_case naming.
FONT_FILES=(
    "${SRC_FONTS}/BebasNeue-Regular.ttf       ${DEST_FONTS}/bebas_neue_regular.ttf"
    "${SRC_FONTS}/RussoOne-Regular.ttf        ${DEST_FONTS}/russo_one_regular.ttf"
    "${SRC_FONTS}/ChakraPetch-Regular.ttf     ${DEST_FONTS}/chakra_petch_regular.ttf"
    "${SRC_FONTS}/ChakraPetch-Bold.ttf        ${DEST_FONTS}/chakra_petch_bold.ttf"
    "${SRC_FONTS}/ChakraPetch-Light.ttf       ${DEST_FONTS}/chakra_petch_light.ttf"
    "${SRC_FONTS}/ChakraPetch-Italic.ttf      ${DEST_FONTS}/chakra_petch_italic.ttf"
)

# Optional cards-head — the iOS pipeline produces this as
# BOBAPlaybook/cards-head.json. We pull from there if present, else
# generate a 500-card slice from cards.json on the fly.
HEAD_SRC="${REPO_ROOT}/BOBAPlaybook/cards-head.json"
HEAD_DEST="${DEST_ASSETS}/cards-head.json"

case "$mode" in
    --check)
        drift=0
        for entry in "${SHARED_FILES[@]}" "${FONT_FILES[@]}"; do
            src="${entry%% *}"
            dest="${entry##* }"
            if ! diff -q "$src" "$dest" >/dev/null 2>&1; then
                echo "DRIFT: $(basename "$dest")"
                drift=1
            fi
        done
        # cards-head check (head is generated from cards.json if missing
        # at source — only diff when source exists).
        if [[ -f "${HEAD_SRC}" ]]; then
            if ! diff -q "${HEAD_SRC}" "${HEAD_DEST}" >/dev/null 2>&1; then
                echo "DRIFT: cards-head.json"
                drift=1
            fi
        fi
        exit "$drift"
        ;;
    update|"")
        for entry in "${SHARED_FILES[@]}"; do
            src="${entry%% *}"
            dest="${entry##* }"
            cp "$src" "$dest"
            echo "  synced $(basename "$dest")"
        done
        for entry in "${FONT_FILES[@]}"; do
            src="${entry%% *}"
            dest="${entry##* }"
            if [[ -f "$src" ]]; then
                cp "$src" "$dest"
                echo "  synced $(basename "$dest")"
            else
                echo "  SKIPPED $(basename "$dest") — source missing at $src"
            fi
        done
        # Head: prefer the iOS-generated one; fall back to a 500-card
        # slice via jq if absent.
        if [[ -f "${HEAD_SRC}" ]]; then
            cp "${HEAD_SRC}" "${HEAD_DEST}"
            echo "  synced cards-head.json (from iOS)"
        elif command -v jq >/dev/null 2>&1; then
            jq '.[0:500]' "${SRC_DATA}/cards.json" > "${HEAD_DEST}"
            echo "  generated cards-head.json (500-card slice via jq)"
        else
            echo "  WARNING: cards-head.json not synced (no source + no jq). M0 first-paint will use the full catalog instead."
        fi
        ;;
    *)
        echo "Usage: $0 [--check]"
        exit 2
        ;;
esac
