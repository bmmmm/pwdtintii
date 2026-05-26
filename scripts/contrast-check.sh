#!/usr/bin/env bash
# WCAG-style contrast check for every family × shade vs common foregrounds.
# Flags combos below WCAG 3.0 (large UI text) and below 4.5 (body text).
# Usage: scripts/contrast-check.sh [palette.tsv]

set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
PALETTE="${1:-${PWDTINTII_PALETTE:-${SELF_DIR}/../palettes/default.tsv}}"

# Foregrounds we care about
read -r -d '' FGS <<'EOF' || true
white	#ffffff
text	#d0d0d0
ghost	#dcdcdc
EOF

python3 - "$PALETTE" <<'PY'
import sys

palette = sys.argv[1]

def lum(hexstr):
    h = hexstr.lstrip('#')
    r,g,b = (int(h[i:i+2],16)/255 for i in (0,2,4))
    def lin(c): return c/12.92 if c <= 0.03928 else ((c+0.055)/1.055)**2.4
    return 0.2126*lin(r) + 0.7152*lin(g) + 0.0722*lin(b)

def contrast(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la+0.05)/(lb+0.05)

fgs = {"white":"#ffffff", "text":"#d0d0d0", "ghost":"#dcdcdc"}

print()
print(f"{'family.shade':<18}" + "  ".join(f"{n:<14}" for n in fgs))
print('-'*70)

bad_count = 0
warn_count = 0
with open(palette) as f:
    for line in f:
        parts = line.rstrip('\n').split('\t')
        if len(parts) < 5: continue
        fam = parts[0]
        if fam in ('family','') or fam.startswith('#'): continue
        for i, hex in enumerate(parts[1:5]):
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
            print(row)

print()
print(f"WCAG: ≥4.5 body text · 3.0-4.5 large UI · <3.0 unreadable")
print(f"Summary: {bad_count} unreadable, {warn_count} marginal")
PY
