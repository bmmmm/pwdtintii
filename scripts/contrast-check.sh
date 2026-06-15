#!/usr/bin/env bash
# Contrast check for every family × shade vs the foregrounds that match the
# palette's theme: dark-background palettes are checked against light text,
# light-background palettes against dark text. The text set is auto-picked from
# the palette's mean luminance, or forced with `dark`/`light` as arg 2.
# Reports the WCAG 2.x ratio (flags <3.0 large UI / <4.5 body), the APCA Lc
# perceptual contrast, and the best-readable foreground per shade.
# Usage: scripts/contrast-check.sh [palette.tsv] [auto|dark|light]

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PALETTE="${1:-${PWDTINTII_PALETTE:-${SELF_DIR}/../palettes/default.tsv}}"
THEME="${2:-auto}"

if [[ ! -f "$PALETTE" ]]; then
  echo "palette not found: $PALETTE" >&2
  exit 1
fi

case "$THEME" in
  auto|dark|light) ;;
  *) echo "theme must be auto, dark, or light (got: $THEME)" >&2; exit 1 ;;
esac

# Foregrounds we check against live in the Python block below (single source).
python3 - "$PALETTE" "$THEME" <<'PY'
import sys

palette, theme = sys.argv[1], sys.argv[2]

def lum(hexstr):
    h = hexstr.lstrip('#')
    r,g,b = (int(h[i:i+2],16)/255 for i in (0,2,4))
    def lin(c): return c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b)

def contrast(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la+0.05)/(lb+0.05)

# ── APCA SA98G v0.1.9 — perceptual contrast Lc (constants from apca-w3.js).
# Signed: + dark text on light bg, - light text on dark bg; magnitude = readability.
_SR, _SG, _SB, _TRC = 0.2126729, 0.7151522, 0.0721750, 2.4
_BLK_THR, _BLK_CLMP = 0.022, 1.414
_N_BG, _N_TX, _R_BG, _R_TX = 0.56, 0.57, 0.65, 0.62
_SCALE, _OFFSET, _LOCLIP, _DYMIN = 1.14, 0.027, 0.1, 0.0005

def _apca_y(hexstr):
    h = hexstr.lstrip('#')
    r,g,b = (int(h[i:i+2],16)/255 for i in (0,2,4))
    y = _SR*r**_TRC + _SG*g**_TRC + _SB*b**_TRC
    return y + (_BLK_THR - y)**_BLK_CLMP if y <= _BLK_THR else y

def apca_lc(txt, bg):
    ty, by = _apca_y(txt), _apca_y(bg)
    if abs(by - ty) < _DYMIN: return 0.0
    if by > ty:
        s = (by**_N_BG - ty**_N_TX) * _SCALE
        out = 0.0 if s < _LOCLIP else s - _OFFSET
    else:
        s = (by**_R_BG - ty**_R_TX) * _SCALE
        out = 0.0 if s > -_LOCLIP else s + _OFFSET
    return out * 100.0

# Best foreground: the theme-appropriate candidate that maximises |Lc|.
_CAND = {
    'dark':  ['#ffffff', '#f0f0f0', '#d0d0d0', '#b0b0b0'],
    'light': ['#000000', '#1a1a1a', '#303030', '#505050'],
}

def _yiq(hexstr):
    h = hexstr.lstrip('#')
    r,g,b = (int(h[i:i+2],16) for i in (0,2,4))
    return (r*299 + g*587 + b*114)//1000

def best_fg(bg, theme):
    cand = _CAND['light'] if (theme == 'light' or _yiq(bg) >= 128) else _CAND['dark']
    return max(cand, key=lambda fg: abs(apca_lc(fg, bg)))

# Collect shades first so the theme can be auto-detected from mean luminance.
rows = []
with open(palette) as f:
    for line in f:
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 5: continue
        fam = parts[0]
        if fam in ('family','') or fam.startswith('#'): continue
        rows.append((fam, parts[1:5]))

if theme == 'auto':
    shades = [h for _, hexes in rows for h in hexes]
    mean = sum(lum(h) for h in shades) / max(len(shades), 1)
    theme = 'light' if mean > 0.2 else 'dark'

# Dark background -> light text; light background -> dark text.
fg_sets = {
    'dark':  {"white":"#ffffff", "text":"#d0d0d0", "ghost":"#dcdcdc"},
    'light': {"black":"#000000", "text":"#303030", "ghost":"#242424"},
}
fgs = fg_sets[theme]

print()
print(f"palette: {palette}")
print(f"theme:   {theme} background, {'light' if theme == 'dark' else 'dark'} text")
print()
print(f"{'family.shade':<18}" + "  ".join(f"{n:<14}" for n in fgs) + "  APCA-Lc  best-fg")
print('-'*78)

bad_count = 0
warn_count = 0
for fam, hexes in rows:
    for i, hex in enumerate(hexes):
        row = f"{fam+'.s'+str(i):<18}"
        for fname, fhex in fgs.items():
            c = contrast(hex, fhex)
            if c < 3.0:
                flag = "X"; bad_count += 1
            elif c < 4.5:
                flag = "!"; warn_count += 1
            else:
                flag = " "
            row += f"  {flag}{c:>6.2f}      "
        text_fg = list(fgs.values())[1]
        bfg = best_fg(hex, theme)
        row += f"  {apca_lc(text_fg, hex):>+6.1f}  {bfg} ({apca_lc(bfg, hex):+.0f})"
        print(row)

print()
print(f"WCAG: ≥4.5 body text · 3.0-4.5 large UI · <3.0 unreadable")
print(f"APCA: |Lc| ≥75 body · 60-75 large UI · <45 sub-readable")
print(f"Summary: {bad_count} unreadable, {warn_count} marginal")
PY
