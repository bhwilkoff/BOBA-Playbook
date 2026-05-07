#!/usr/bin/env bash
# pipeline/recognition/sync_mirror.sh
#
# Sync the CardRecognitionCLI's Mirror/ folder against the authoritative
# iOS scanner sources. Run this whenever the iOS scoring logic changes.
#
# Modes:
#   ./sync_mirror.sh            update mirror in place
#   ./sync_mirror.sh --check    compare mirror vs source; nonzero exit
#                               on drift (CI uses this)
#   ./sync_mirror.sh --diff     show the diff (no copy, no exit code)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIRROR="${REPO_ROOT}/pipeline/recognition/CardRecognitionCLI/Sources/CardRecognitionCLI/Mirror"

# (mirror_file source_file)
MIRRORS=(
    "Card.swift            ${REPO_ROOT}/BOBAPlaybook/Models/Card.swift"
    "ScanMatching.swift    ${REPO_ROOT}/BOBAPlaybook/Views/Scan/ScanMatching.swift"
)

mode="${1:-update}"

case "$mode" in
    --check)
        drift=0
        for entry in "${MIRRORS[@]}"; do
            mirror_name="${entry%% *}"
            src_path="${entry##* }"
            if ! diff -q "${MIRROR}/${mirror_name}" "${src_path}" >/dev/null 2>&1; then
                echo "DRIFT: ${mirror_name}"
                drift=1
            fi
        done
        # ScannerTypes.swift is intentionally not byte-identical (it has
        # the load(from:) replacement for loadFromBundle) — skip it from
        # the strict drift check. CI relies on swift build to catch real
        # API changes there.
        exit "$drift"
        ;;
    --diff)
        for entry in "${MIRRORS[@]}"; do
            mirror_name="${entry%% *}"
            src_path="${entry##* }"
            echo "=== ${mirror_name} ==="
            diff "${MIRROR}/${mirror_name}" "${src_path}" || true
        done
        ;;
    update|"")
        for entry in "${MIRRORS[@]}"; do
            mirror_name="${entry%% *}"
            src_path="${entry##* }"
            cp "${src_path}" "${MIRROR}/${mirror_name}"
            echo "  synced ${mirror_name}"
        done
        echo "ScannerTypes.swift not auto-synced (manual extraction — see _MIRROR.md)"
        ;;
    *)
        echo "usage: $0 [--check|--diff|update]"
        exit 64
        ;;
esac
