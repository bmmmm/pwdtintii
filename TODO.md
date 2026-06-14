# TODO — pwdtintii

Entry point for picking up work. Read this first, then pick a section.

## Status

0.2.0 — released 2026-06-14 (`v0.2.0`). The `pt` action hub (looping menu, back
navigation, stale-shell detection), full-height dimmed picker preview, plus the
0.1.x bash/zsh drift fixes — locked down with a 48-test bats suite + Forgejo CI
(see CHANGELOG). Still alpha. Dotfiles already source the plugin (`~/.zshrc`).

## Next session — start here

0.2.0 is shipped (`v0.2.0`) and live on the public GitHub mirror. Unreleased
since (see CHANGELOG): GitHub mirror, macOS CI matrix + release job, `pt off`
(real disable + OSC 111 reset), `pt doctor`, PWD-cached prompt hot-path, palette
validation, plugin-manager install docs, `pt pick auto` unpin fix, and a
light-terminal-theme palette (`palettes/light.tsv` + `gen-light-palette.py`,
theme-aware contrast/preview). Suite is 66 green.

**Verified in Ghostty** (the sandbox can't emit OSC / run a live tty): `pt
doctor` → osc 11 "supported", `pt off` resets the background, `pt pick`
re-enables. Remaining pre-release step: cut the next tag (`v0.3.0`) to exercise
the still-untested release job, after a final `tests/run.sh`.

## Release smoke test (fresh Ghostty)

1. **Tinting + the `pt` hub**
   - Open a new tab in a git repo, expect tint matching `pt list` output.
   - `cd` into a different repo → tint should change at next prompt.
   - `cmd+d` (split) → same family, different shade.
   - Run `pt` → fzf action menu opens; arrow keys show each action's
     description; pick `pick` → family picker opens.
   - In the family picker: arrow keys preview live, all **four** shades stay
     distinct against the dimmed background, ENTER pins.
   - Back behaviour: from the menu pick `list` → it prints, then a keypress
     returns you to the menu. q quits the hub; arrow keys / ESC / letters all
     return to the menu (no stray `[A` in the search). ESC steps back one level:
     picker → menu, menu → shell.
   - Staleness: edit + save the plugin file → next `pt` shows `plugin changed —
     re-source` in the header (and `pt help` notes it); gone after re-sourcing.
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
      WCAG-readable shades). contrast-check + preview are now theme-aware.
      ← erledigt 2026-06-14
  - [ ] Follow-up (needs real-terminal verify): the live fzf picker preview
        (`bin/pwdtintii cmd_preview_family` / focus tone) still renders light
        text — on a light palette the preview pane reads poorly though the actual
        tint is correct. Make the picker preview theme-aware too.

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
│   ├── default.tsv         # 37 families × 4 shades
│   └── README.md
├── scripts/
│   ├── preview.sh          # visual palette dump
│   └── contrast-check.sh   # WCAG check
├── tests/                  # bats suite coupling bash + zsh
│   ├── helper.bash
│   ├── parity.bats         # cross-shell key/family/hash parity
│   ├── plugin.bats         # bash plugin behaviour
│   ├── cli.bats            # bin/pwdtintii subcommands
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
