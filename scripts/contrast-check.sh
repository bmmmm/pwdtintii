#!/usr/bin/env bash
# Backward-compatible wrapper around the contrast engine (scripts/contrast.py).
# Kept so `pt contrast` and older callers keep working; new code (the viewer)
# calls contrast.py directly, including its --row machine mode.
# Usage: scripts/contrast-check.sh [palette.tsv] [auto|dark|light]

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PALETTE="${1:-${PWDTINTII_PALETTE:-${SELF_DIR}/../palettes/default.tsv}}"
exec python3 "${SELF_DIR}/contrast.py" "$PALETTE" "${2:-auto}"
