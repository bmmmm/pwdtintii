#!/usr/bin/env bash
# Print all families × 4 shades with sample foregrounds.
# Usage: scripts/preview.sh [palette.tsv]

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PALETTE="${1:-${PWDTINTII_PALETTE:-${SELF_DIR}/../palettes/default.tsv}}"

if [[ ! -f "$PALETTE" ]]; then
  echo "palette not found: $PALETTE" >&2
  exit 1
fi

hex_to_rgb() {
  local hex="${1#\#}"
  printf '%d %d %d\n' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

cell() {
  local hex="$1" label="$2" italic="${3:-}"
  read -r r g b < <(hex_to_rgb "$hex")
  local fg=220   # ghost grey for now
  if [[ "$label" == "white" ]]; then fg=255; fi
  printf '\e[48;2;%d;%d;%dm\e[38;2;%d;%d;%dm%s %s \e[0m' \
    "$r" "$g" "$b" "$fg" "$fg" "$fg" "$italic" "$label"
}

printf '\n── Palette: %s ──\n\n' "$PALETTE"
printf '%-15s' "family"
for s in s0 s1 s2 s3; do printf '  %-32s' "$s"; done
echo

while IFS=$'\t' read -r family s0 s1 s2 s3; do
  [[ -z "$family" || "$family" == "family" || "$family" == \#* ]] && continue
  printf '%-15s' "$family"
  for hex in "$s0" "$s1" "$s2" "$s3"; do
    cw=$(cell "$hex" "white")
    cg=$(cell "$hex" "ghost" $'\e[3m')
    printf '  %s%s %s' "$cw" "$cg" "$hex"
  done
  echo
done < "$PALETTE"
echo
