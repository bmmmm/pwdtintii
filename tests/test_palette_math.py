#!/usr/bin/env python3
"""Unit tests for scripts/palette_math.py — the shared color-math module.

Self-contained (no pytest): asserts and exits non-zero on the first failure, so
a single bats test can run it. The APCA cases are the published apca-w3.js
reference values; pinning them locks the SA98G constants against a copy-paste
drift the palette-level black-box CLI tests would not catch.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "scripts"))
import palette_math as m  # noqa: E402


def approx(a, b, tol=0.01):
    return abs(a - b) <= tol


def main():
    # ── hex_to_rgb ────────────────────────────────────────────────────────────
    assert m.hex_to_rgb("#000000") == (0.0, 0.0, 0.0)
    assert m.hex_to_rgb("#ffffff") == (1.0, 1.0, 1.0)
    # leading '#' optional; channels are exact n/255 fractions
    assert m.hex_to_rgb("ff8000") == (255 / 255, 128 / 255, 0 / 255)

    # ── WCAG relative luminance ───────────────────────────────────────────────
    assert approx(m.wcag_lum_hex("#ffffff"), 1.0)
    assert approx(m.wcag_lum_hex("#000000"), 0.0)
    assert approx(m.wcag_lum_hex("#808080"), 0.2159, tol=0.0005)
    # wcag_lum(r,g,b) and wcag_lum_hex(h) must agree on the same color
    assert approx(m.wcag_lum(*m.hex_to_rgb("#0a38a8")), m.wcag_lum_hex("#0a38a8"), tol=1e-9)

    # ── integer YIQ (matches the shell hot path _pt_lum) ──────────────────────
    assert m.yiq("#ffffff") == 255
    assert m.yiq("#000000") == 0
    assert m.yiq("#001f70") == 30   # dark blue shade0 -> not light (< 128)
    assert m.yiq("#e5eaf6") >= 128  # pale light-palette shade -> light

    # ── APCA SA98G — published apca-w3.js reference pairs (text on bg) ─────────
    assert approx(m.apca_lc("#000000", "#ffffff"), 106.04)   # black on white
    assert approx(m.apca_lc("#ffffff", "#000000"), -107.88)  # white on black
    assert approx(m.apca_lc("#888888", "#ffffff"), 63.06)    # mid-gray on white
    assert m.apca_lc("#777777", "#777777") == 0.0            # no luminance delta
    # sign convention: dark-on-light positive, light-on-dark negative
    assert m.apca_lc("#000000", "#ffffff") > 0
    assert m.apca_lc("#ffffff", "#000000") < 0

    # ── best_fg picks the legible candidate per theme ─────────────────────────
    assert m.best_fg("#001f70", "dark") == "#ffffff"   # white pops on deep blue
    assert m.best_fg("#e5eaf6", "light") == "#000000"  # black on a pale tint
    # the returned fg is one of the theme's candidates
    assert m.best_fg("#123456", "dark") in m._CAND["dark"]

    # ── read_families: TSV parsing (skips header/comment/blank/short rows) ─────
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".tsv", delete=False) as tf:
        tf.write("family\tshade0\tshade1\tshade2\tshade3\n")    # header  -> skip
        tf.write("# comment\n")                                 # comment -> skip
        tf.write("\n")                                          # blank   -> skip
        tf.write("blue\t#001f70\t#002d8f\t#0a38a8\t#1442c0\n")  # kept
        tf.write("short\t#001f70\n")                            # <5 cols -> skip
        tf.write("red\t#701f00\t#8f2d00\t#a8380a\t#c04214")     # no trailing \n -> kept
        tmp = tf.name
    fams = m.read_families(tmp)
    os.unlink(tmp)
    assert [f for f, _ in fams] == ["blue", "red"], fams
    assert fams[0] == ("blue", ["#001f70", "#002d8f", "#0a38a8", "#1442c0"]), fams[0]
    assert len(fams[1][1]) == 4 and fams[1][0] == "red"    # newline-less last row kept

    print("palette_math: all unit assertions passed")


if __name__ == "__main__":
    try:
        main()
    except AssertionError:
        import traceback
        traceback.print_exc()
        sys.exit(1)
