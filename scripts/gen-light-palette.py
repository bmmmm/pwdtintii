#!/usr/bin/env python3
"""Derive palettes/light.tsv from palettes/default.tsv.

Light-terminal-theme variant. The families and their order are copied verbatim
from default.tsv — the directory hash maps key -> families[hash % N], so the
order is load-bearing: a given directory must land on the same family name in
both palettes, otherwise switching themes reshuffles every workspace's hue.

Only the shades change: each family's hue is taken from its brightest dark
shade and re-rendered as a pale tint at a fixed WCAG-luminance ladder, so every
shade clears WCAG 4.5 against dark foreground text instead of light.

Regenerate after editing default.tsv, then re-validate:
    scripts/gen-light-palette.py
    scripts/contrast-check.sh palettes/light.tsv light
"""
import colorsys
import os
import sys

from palette_math import hex_to_rgb, wcag_lum, read_families

SELF_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(SELF_DIR, "..", "palettes", "default.tsv")
LIGHT = os.path.join(SELF_DIR, "..", "palettes", "light.tsv")

# Target WCAG relative luminance per shade index (s0 deepest tint -> s3 palest).
# All clear ~0.308 (the WCAG 4.5 floor vs #303030 dark text); s0 is lifted to
# 0.51 so the deepest tint also clears the APCA |Lc| 60 readability floor that
# palette.bats enforces, matching the dark palette. The spread keeps splits
# distinguishable.
LADDER = [0.51, 0.60, 0.72, 0.82]
# Light and saturated cannot coexist; cap saturation so the pale tints land.
SAT_CAP = 0.50


def rgb_to_hex(r, g, b):
    return "#%02x%02x%02x" % (round(r * 255), round(g * 255), round(b * 255))


def family_hue_sat(shades):
    """Hue + capped saturation from the brightest (most chromatic) dark shade."""
    best = max(shades, key=lambda h: sum(hex_to_rgb(h)))
    r, g, b = hex_to_rgb(best)
    hue, _light, sat = colorsys.rgb_to_hls(r, g, b)
    return hue, min(sat, SAT_CAP)


def shade_for(hue, sat, target_lum):
    """Binary-search HLS lightness until WCAG luminance reaches the target."""
    lo, hi = 0.0, 1.0
    for _ in range(40):
        mid = (lo + hi) / 2
        r, g, b = colorsys.hls_to_rgb(hue, mid, sat)
        if wcag_lum(r, g, b) < target_lum:
            lo = mid
        else:
            hi = mid
    r, g, b = colorsys.hls_to_rgb(hue, (lo + hi) / 2, sat)
    return rgb_to_hex(r, g, b)


def main():
    # Optional output path (default: palettes/light.tsv) — lets the test suite
    # regenerate to a temp file and diff, without clobbering the tracked palette.
    out_path = sys.argv[1] if len(sys.argv) > 1 else LIGHT
    rows = read_families(DEFAULT)
    out = ["family\tshade0\tshade1\tshade2\tshade3"]
    for fam, shades in rows:
        hue, sat = family_hue_sat(shades)
        light = [shade_for(hue, sat, t) for t in LADDER]
        out.append("\t".join([fam] + light))
    with open(out_path, "w") as f:
        f.write("\n".join(out) + "\n")
    print("wrote %s (%d families)" % (out_path, len(rows)))


if __name__ == "__main__":
    main()
