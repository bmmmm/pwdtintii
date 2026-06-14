# Palettes

Each palette is a TSV file: `family<TAB>shade0<TAB>shade1<TAB>shade2<TAB>shade3`.

- 4 shades per family, darkest → lightest.
- Hex format: `#rrggbb`.
- Lines starting with `#` and the header row are ignored.

## Shipped palettes

- `default.tsv` — dark backgrounds for dark terminal themes (the default).
- `light.tsv` — pale backgrounds for light terminal themes. Select it before
  sourcing the plugin:
  `PWDTINTII_PALETTE=~/.local/share/pwdtintii/palettes/light.tsv`.

`light.tsv` is **generated** from `default.tsv` by `scripts/gen-light-palette.py`,
not hand-edited. It copies the family list and order verbatim — the order is
load-bearing (see Design notes) so both palettes must agree on which family a
directory lands on — and re-renders each family's hue as a pale tint on a
WCAG-luminance ladder tuned for dark text.

## Adding a new family

1. Append a new row to `default.tsv` (or use your own palette file via `PWDTINTII_PALETTE`).
2. Run `pt reload` (or `pwdtintii_reload`).
3. Pick a shade range that stays readable with your standard foreground text —
   keep luminance below ~0.15 for `s3` if you use a `#888`-grade ghost color.
   The included `scripts/contrast-check.sh` flags problematic shades (it checks
   light-background palettes against dark text — auto-detected, or forced with a
   `dark`/`light` second argument).
4. If you ship the light variant, regenerate and re-validate it:
   ```sh
   scripts/gen-light-palette.py
   scripts/contrast-check.sh palettes/light.tsv light   # expect: 0 unreadable, 0 marginal
   ```

## Design notes

- Order matters: the hash maps `key → families[hash mod N]`, so appending
  reshuffles existing keys. If you want stable colors across palette changes,
  append-only.
- Shade indices (0..3) are used per-directory for splits; the brightness
  delta between `s0` and `s3` is what differentiates panes in the same dir.
  Keep that delta visible but moderate.
