#!/usr/bin/env python3
"""Shared color math for pwdtintii's palette scripts.

The single home for the shared palette code: hex + palette-TSV parsing, WCAG 2.x
relative luminance, integer YIQ, and the APCA SA98G contrast engine. Imported by
contrast.py and gen-light-palette.py; since each is invoked by an absolute path,
Python puts the scripts/ dir on sys.path[0] and the bare `import palette_math`
resolves. No import-time side effects, so it's unit-testable directly
(tests/test_palette_math.py).
"""


# ── hex ───────────────────────────────────────────────────────────────────────
def hex_to_rgb(h):
    """#rrggbb (or rrggbb) -> (r, g, b) as 0..1 floats."""
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


# ── palette TSV ────────────────────────────────────────────────────────────────
def read_families(path):
    """Parse a palette TSV into [(family, [s0, s1, s2, s3]), ...].

    Skips the header row, blank lines, and '#' comments; ignores any row with
    fewer than five tab fields. A newline-less last row is still captured. Shared
    by contrast.py and gen-light-palette.py (the shells parse the palette
    themselves on the prompt hot path — see _pwdtintii_load_palette)."""
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            fam = parts[0]
            if fam in ("family", "") or fam.startswith("#"):
                continue
            rows.append((fam, parts[1:5]))
    return rows


# ── WCAG 2.x ──────────────────────────────────────────────────────────────────
def _linearize(c):
    """sRGB component (0..1) -> linear-light, per WCAG 2.x."""
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def wcag_lum(r, g, b):
    """WCAG 2.x relative luminance from 0..1 sRGB components."""
    return 0.2126 * _linearize(r) + 0.7152 * _linearize(g) + 0.0722 * _linearize(b)


def wcag_lum_hex(h):
    """WCAG 2.x relative luminance from a #rrggbb hex."""
    return wcag_lum(*hex_to_rgb(h))


# ── YIQ ───────────────────────────────────────────────────────────────────────
def yiq(h):
    """Integer YIQ perceived luminance (0..255) from a #rrggbb hex — the same
    weighting the shell hot path uses (_pt_lum in bin/pwdtintii). >= 128 reads
    as a light color."""
    s = h.lstrip("#")
    r, g, b = (int(s[i:i + 2], 16) for i in (0, 2, 4))
    return (r * 299 + g * 587 + b * 114) // 1000


# ── APCA SA98G v0.1.9 — perceptual contrast Lc (constants from apca-w3.js). ─────
# Signed: + dark text on light bg, - light text on dark bg; magnitude = readability.
_SR, _SG, _SB, _TRC = 0.2126729, 0.7151522, 0.0721750, 2.4
_BLK_THR, _BLK_CLMP = 0.022, 1.414
_N_BG, _N_TX, _R_BG, _R_TX = 0.56, 0.57, 0.65, 0.62
_SCALE, _OFFSET, _LOCLIP, _DYMIN = 1.14, 0.027, 0.1, 0.0005


def _apca_y(hexstr):
    r, g, b = hex_to_rgb(hexstr)
    y = _SR * r**_TRC + _SG * g**_TRC + _SB * b**_TRC
    return y + (_BLK_THR - y) ** _BLK_CLMP if y <= _BLK_THR else y


def apca_lc(txt, bg):
    """APCA lightness contrast Lc of text over bg (both #rrggbb). Signed; the
    magnitude is the readability score."""
    ty, by = _apca_y(txt), _apca_y(bg)
    if abs(by - ty) < _DYMIN:
        return 0.0
    if by > ty:
        s = (by ** _N_BG - ty ** _N_TX) * _SCALE
        out = 0.0 if s < _LOCLIP else s - _OFFSET
    else:
        s = (by ** _R_BG - ty ** _R_TX) * _SCALE
        out = 0.0 if s > -_LOCLIP else s + _OFFSET
    return out * 100.0


# Best foreground: the theme-appropriate candidate that maximises |Lc|.
_CAND = {
    'dark':  ['#ffffff', '#f0f0f0', '#d0d0d0', '#b0b0b0'],
    'light': ['#000000', '#1a1a1a', '#303030', '#505050'],
}


def best_fg(bg, theme):
    """The theme-appropriate text candidate that maximises |APCA Lc| on bg."""
    cand = _CAND['light'] if (theme == 'light' or yiq(bg) >= 128) else _CAND['dark']
    return max(cand, key=lambda fg: abs(apca_lc(fg, bg)))
