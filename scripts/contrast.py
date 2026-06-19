#!/usr/bin/env python3
"""Contrast engine for pwdtintii palettes: WCAG 2.x ratio + APCA Lc + best fg.

Three output modes:
  contrast.py <palette.tsv> [auto|dark|light]
      Human-readable table: every family.shade vs the theme foregrounds, with
      the WCAG ratio, the APCA Lc, and the best-readable foreground per shade.
  contrast.py <palette.tsv> [auto|dark|light] --row <family>
      Machine-readable rows for one family, one shade per line, tab-separated:
      idx<TAB>hex<TAB>wcag_ratio<TAB>lc<TAB>best_fg
      (the viewer's colored contrast preview parses this).
  contrast.py <palette.tsv> [auto|dark|light] --check-floor <N>
      Guard mode: exit 1 if any shade's APCA |Lc| against the theme text is
      below N, listing the offenders; exit 0 if all clear. The test suite uses
      it to enforce the readability floor on both palettes.

The text set is auto-picked from the palette's mean luminance, or forced with
dark/light. WCAG flags <3.0 (large UI) / <4.5 (body); the APCA Lc magnitude
reads >=75 body, 60-75 large UI, <45 sub-readable.
"""
import os
import sys

from palette_math import wcag_lum_hex as lum, apca_lc, best_fg, read_families

# ── arg parsing ──────────────────────────────────────────────────────────────
args = sys.argv[1:]
row_family = None
if "--row" in args:
    i = args.index("--row")
    if i + 1 >= len(args):
        sys.stderr.write("--row needs a family name\n")
        sys.exit(2)
    row_family = args[i + 1]
    del args[i:i + 2]

check_floor = None
if "--check-floor" in args:
    i = args.index("--check-floor")
    if i + 1 >= len(args):
        sys.stderr.write("--check-floor needs a number\n")
        sys.exit(2)
    try:
        check_floor = float(args[i + 1])
    except ValueError:
        sys.stderr.write(f"--check-floor needs a number (got: {args[i + 1]})\n")
        sys.exit(2)
    del args[i:i + 2]

palette = args[0] if args else ""
theme = args[1] if len(args) > 1 else "auto"

if not palette or not os.path.isfile(palette):
    sys.stderr.write(f"palette not found: {palette}\n")
    sys.exit(1)
if theme not in ("auto", "dark", "light"):
    sys.stderr.write(f"theme must be auto, dark, or light (got: {theme})\n")
    sys.exit(1)


# ── WCAG 2.x ──────────────────────────────────────────────────────────────────
# lum() is wcag_lum_hex from palette_math; apca_lc/best_fg are the APCA engine,
# also from palette_math (the single home for the perceptual math).
def contrast(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)


# ── load palette ───────────────────────────────────────────────────────────────
rows = read_families(palette)

if theme == 'auto':
    shades = [h for _, hexes in rows for h in hexes]
    mean = sum(lum(h) for h in shades) / max(len(shades), 1)
    theme = 'light' if mean > 0.2 else 'dark'

fg_sets = {
    'dark':  {"white": "#ffffff", "text": "#d0d0d0", "ghost": "#dcdcdc"},
    'light': {"black": "#000000", "text": "#303030", "ghost": "#242424"},
}
fgs = fg_sets[theme]
text_fg = list(fgs.values())[1]

# ── machine mode: one family, tab-separated rows ─────────────────────────────────
if row_family is not None:
    for fam, hexes in rows:
        if fam != row_family:
            continue
        for i, hexv in enumerate(hexes):
            print(f"{i}\t{hexv}\t{contrast(hexv, text_fg):.2f}\t"
                  f"{apca_lc(text_fg, hexv):+.1f}\t{best_fg(hexv, theme)}")
        break
    sys.exit(0)

# ── check mode: enforce an APCA floor for text-on-tint readability ────────────────
if check_floor is not None:
    violations = []
    for fam, hexes in rows:
        for i, hexv in enumerate(hexes):
            lc = abs(apca_lc(text_fg, hexv))
            if lc < check_floor:
                violations.append((f"{fam}.s{i}", hexv, lc))
    label = "light text" if theme == "dark" else "dark text"
    print(f"APCA floor {check_floor:.0f}: {text_fg} ({label}) on {palette}")
    for name, hexv, lc in violations:
        print(f"  FAIL {name:<18} {hexv}  Lc {lc:.1f}")
    print(f"Summary: {len(violations)} below floor (APCA |Lc| < {check_floor:.0f})")
    sys.exit(1 if violations else 0)

# ── human mode: full table ──────────────────────────────────────────────────────
print()
print(f"palette: {palette}")
print(f"theme:   {theme} background, {'light' if theme == 'dark' else 'dark'} text")
print()
print(f"{'family.shade':<18}" + "  ".join(f"{n:<14}" for n in fgs) + "  APCA-Lc  best-fg")
print('-' * 78)

bad_count = 0
warn_count = 0
for fam, hexes in rows:
    for i, hexv in enumerate(hexes):
        row = f"{fam + '.s' + str(i):<18}"
        for fname, fhex in fgs.items():
            c = contrast(hexv, fhex)
            if c < 3.0:
                flag = "X"
                bad_count += 1
            elif c < 4.5:
                flag = "!"
                warn_count += 1
            else:
                flag = " "
            row += f"  {flag}{c:>6.2f}      "
        bfg = best_fg(hexv, theme)
        row += f"  {apca_lc(text_fg, hexv):>+6.1f}  {bfg} ({apca_lc(bfg, hexv):+.0f})"
        print(row)

print()
print("WCAG: ≥4.5 body text · 3.0-4.5 large UI · <3.0 unreadable")
print("APCA: |Lc| ≥75 body · 60-75 large UI · <45 sub-readable")
print(f"Summary: {bad_count} unreadable, {warn_count} marginal")
