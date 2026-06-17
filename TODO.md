# TODO — pwdtintii

Entry point for picking up work. Read this first, then pick a section.

## Status

0.3.0 released 2026-06-15 (`v0.3.0`); unreleased work sits on top of it — see
the CHANGELOG `[Unreleased]` section (the merged `pt view` browser, APCA scores
in `pt contrast`, high-contrast fzf menus over the live tint). 0.3.0 itself
added `pt off`, `pt doctor`, a light-terminal palette (`light.tsv`) + ctrl-t
picker toggle, a self-reloading `pt`, a PWD-cached prompt hot-path, palette
validation, macOS CI, and the public GitHub mirror. Covered by the bats suite
(`grep -c '^@test' tests/*.bats` for the live count). Still alpha. Dotfiles
already source the plugin (`~/.zshrc`).

## Next session — start here

The `ctrl-t` live-tint saga is resolved: in both `pt pick` and `pt view` the
terminal background now flips together with the list/swatches (routed through
fzf's coordinated `execute-silent`, not a raw `transform` write fzf dropped), and
ENTER/ESC close flash-free (inline sub-100% fzf). `pt pick` is user-confirmed on
a real terminal; `pt view` rides the same fix path. See the CHANGELOG
`[Unreleased]` → Fixed for the full list (also: `$?` preservation, the
palette-path normalization that kept the toggle alive across a commit, array
`PROMPT_COMMAND`, newline-less palettes, zsh `nounset`).

Remaining live spot-check (the command sandbox has no tty for OSC 11 / fzf): a
fresh-terminal pass of the release checklist below — the picker ctrl-t flip,
light-group preview legibility, and a clean flash-free exit.

The bats suite is green on a real shell (115 tests). Under the command sandbox
the `zsh pick_shade skips a live PID` test reads red because `kill -0` is blocked
there — not a real failure; run the suite on a real shell to confirm.

## Release smoke test (fresh Ghostty)

1. **Tinting + the `pt` hub**
   - Open a new tab in a git repo, expect tint matching `pt list` output.
   - `cd` into a different repo → tint should change at next prompt.
   - `cmd+d` (split) → same family, different shade.
   - Run `pt` → fzf action menu opens; arrow keys show each action's
     description; pick `pick` → family picker opens.
   - In the family picker: arrow keys preview live, all **four** shades stay
     distinct against the dimmed background, ENTER pins.
   - ctrl-t flips the dark↔light group (prompt + swatches change); ENTER from
     the light group switches the shell to light and pins. On the light group
     the preview-pane labels read as dark text on the pale swatches (legible),
     not washed-out light text, and the hover/focus background stays light
     (lifts toward white) rather than darkening the terminal under your text.
   - Back behaviour: from the menu pick `list` → it prints, then a keypress
     returns you to the menu. q quits the hub; arrow keys / ESC / letters all
     return to the menu (no stray `[A` in the search). ESC steps back one level:
     picker → menu, menu → shell.
   - Staleness: edit + save the plugin file → next `pt` auto-re-sources it and
     prints `plugin changed on disk — reloaded this shell`; the pinned family
     and shade carry over, and the stale flag clears without a manual re-source.
   - Run `pt pick blue` → directly pins blue.
   - Run `pt help` → command overview prints.

2. **bash-side verify** (Linux later or via `brew install bash` on Mac):
   - `bash --rcfile <(echo "source ~/.local/share/pwdtintii/pwdtintii.plugin.bash")`
   - Confirm `pwdtintii_list` works, OSC 11 emits on prompt.

## Open work (small)

- [ ] Demo GIF for README (asciinema can't capture the color change → screen capture)
- [x] GitHub public mirror — live at github.com/bmmmm/pwdtintii (one-way Forgejo→GitHub, 8h + on-commit) ← erledigt 2026-06-14
- [x] GitHub CI: macOS matrix + release automation ← erledigt 2026-06-14
      - `macos-latest` in the test matrix (BSD awk/`stat -f`/`shasum`, brew bash 4+)
      - Release job on `v*` tags: GitHub Release with the extracted CHANGELOG section
      - Untested until first real tag push — `v0.3.0` will be the first exercise

## Open work (medium)

- [ ] fish shell support — `function --on-event fish_prompt`
- [ ] tmux integration — set per-pane background via `select-pane -P`
- [x] Light-theme palette variant — `palettes/light.tsv`, generated from
      `default.tsv` by `scripts/gen-light-palette.py` (same families/order, pale
      WCAG-readable shades). contrast-check + preview are now theme-aware, and
      `pt pick` has a ctrl-t dark/light group toggle. ← erledigt 2026-06-14
  - [x] Picker preview pane is now high-contrast: text/label tones flip per band
        by perceived luminance (`_pt_text_fg` in `bin/pwdtintii`), dark text on
        pale `light.tsv` swatches. ← erledigt 2026-06-15
    - [x] Live *focus tone* (`emit-family`) is now theme-aware too: dark palette
          dims the darkest shade toward black (~lum 15-28), light palette lifts
          the lightest toward white (~lum 242-244) via `_pt_focus_tone`, so the
          hover background no longer darkens a light terminal theme under the
          user's dark text. ← erledigt 2026-06-15

## Design decisions already made

- **License:** Apache-2.0 (plugin = library + glue, not a copyleft-warranted
  algorithm).
- **No MIT.** No patent grant, no NOTICE.
- **Palette format:** TSV, shell-agnostic, single source of truth across
  zsh + bash plugins + CLI.
- **No persisted dir→family map.** Hash is deterministic, so no state needed.
- **PID-tracked shade registry**, not daemon-based. Dead PIDs GC'd on the fly.
- **Override mechanism kept** (via `PWDTINTII_OVERRIDES_FILE`) but no default
  overrides — local override file is user-side.

## Known caveats

- shasum vs sha1sum: detected at plugin load in **both** shells. If you're on a
  system with neither, the plugin fails loudly at load.
- Ghostty's own shell-integration also defines `_ghostty_precmd` — we use a
  different namespace (`_pwdtintii_*`) so no clash.
- bash 3.2 (macOS default `/bin/bash`) is NOT supported — needs associative
  arrays. Plugin emits an error and bails on load.

## Files

```
pwdtintii/
├── pwdtintii.plugin.zsh    # main zsh plugin
├── pwdtintii.plugin.bash   # main bash plugin (4+)
├── bin/pwdtintii           # CLI companion (fzf preview helper)
├── palettes/
│   ├── default.tsv         # 37 families × 4 shades (dark themes)
│   ├── light.tsv           # pale variant for light themes
│   └── README.md
├── scripts/
│   ├── contrast.py         # WCAG + APCA engine (dump + --row machine mode)
│   ├── contrast-check.sh   # WCAG + APCA check wrapper (needs python3)
│   └── gen-light-palette.py  # regenerates light.tsv from default.tsv
├── tests/                  # bats suite coupling bash + zsh
│   ├── helper.bash
│   ├── parity.bats         # cross-shell key/family/hash parity
│   ├── plugin.bats         # bash plugin behaviour
│   ├── cli.bats            # bin/pwdtintii subcommands
│   ├── palette.bats        # light.tsv parity + contrast-check
│   └── run.sh
├── .github/workflows/
│   └── ci.yml              # shellcheck + zsh -n + bats
├── examples/
│   ├── aliases.zsh         # opt-in pt, ptpick, ...
│   ├── aliases.bash
│   └── overrides.tsv       # template for named overrides
├── LICENSE                 # Apache-2.0
├── NOTICE
├── CHANGELOG.md
├── README.md
└── TODO.md                 # ← you are here
```
