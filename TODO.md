# TODO — pwdtintii

Entry point for picking up work. Read this first, then pick a section.

## Status

0.5.0 released 2026-06-18 (`v0.5.0`, tag set locally — the push is the human's
step): `pt version` backed by a single-source `VERSION` file, `scripts/release.sh`
(release automation), and the fzf live-preview tint made per-pane under tmux — on
top of 0.4.0 (fish shell support, tmux per-pane tinting, the merged `pt view`
browser, APCA scores in `pt contrast`, high-contrast fzf menus) and 0.3.0
(released 2026-06-15: `pt off`, `pt doctor`, a light-terminal palette
(`light.tsv`) + ctrl-t picker toggle, a self-reloading `pt`, a PWD-cached prompt
hot-path, palette validation, macOS CI, and the public GitHub mirror). fish was
live-confirmed; tmux per-pane is now fully verified on real tmux 3.6b — the data
layer (`select-pane -P` sets the focused pane's bg to the computed tone, sibling
panes independent) and the visual look user-confirmed. Covered by the bats suite
(`grep -c '^@test' tests/*.bats` for the live count). Still alpha. Dotfiles
already source the plugin (`~/.zshrc`).

Unreleased since 0.5.0 (see CHANGELOG `[Unreleased]`): `scripts/release.sh` is now
a real dry-run — a preview (without `--yes`) no longer edits the tracked files in
place, so the documented dry-run → `--yes` flow works. The dry-run used to mv the
edits into place, which dirtied the tree and tripped the script's own clean-tree
precondition on the very `--yes` it pointed you to; it now diffs the proposed
edits against the current files and writes nothing until `--yes`.

## Next session — start here

The `ctrl-t` live-tint saga is resolved: in both `pt pick` and `pt view` the
terminal background now flips together with the list/swatches (routed through
fzf's coordinated `execute-silent`, not a raw `transform` write fzf dropped), and
ENTER/ESC close flash-free (inline sub-100% fzf). `pt pick` is user-confirmed on
a real terminal; `pt view` rides the same fix path. See the CHANGELOG
`[0.4.0]` → Fixed for the full list (also: `$?` preservation, the
palette-path normalization that kept the toggle alive across a commit, array
`PROMPT_COMMAND`, newline-less palettes, zsh `nounset`).

The `pt` hub menu also sizes itself to the terminal width now (a0910bb): the list
pane fits its widest action row (no more `··`-ellipsized glosses) and the
description preview reflows to `FZF_PREVIEW_COLUMNS` (no `↳` hard-wraps); on a
terminal too narrow for a side-by-side split the preview stacks below the list.
User-confirmed on a real terminal.

Remaining live spot-check (the command sandbox has no tty for OSC 11 / fzf): a
fresh-terminal pass of the release checklist below — the picker ctrl-t flip,
light-group preview legibility, and a clean flash-free exit. The tmux per-pane
tint (only the focused pane tints while `pt pick` / `pt view` is open) is now
confirmed visually on real tmux 3.6b, on top of the data-layer proof.

The bats suite is green on a real shell and under the command sandbox alike (use
`grep -c '^@test' tests/*.bats` for the live count). The `zsh pick_shade skips a
live PID` test used to read red sandboxed, and the cause was not what it looked
like: zsh nices background jobs by default (`BG_NICE`), the sandbox blocks the
`nice()` syscall, and zsh's `nice(N) failed` warning leaked onto stderr — which
bats `run` merges into the `$output` the test asserts on, turning a correct `1`
into a mismatch. `kill -0` itself works fine. Fixed by `unsetopt bgnice` in
`zsh_eval` (harness-wide), so the test now runs for real everywhere.

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

- [x] GitHub public mirror — live at github.com/bmmmm/pwdtintii (one-way Forgejo→GitHub, 8h + on-commit) ← erledigt 2026-06-14
- [x] GitHub CI: macOS matrix + release automation ← erledigt 2026-06-14
      - `macos-latest` in the test matrix (BSD awk/`stat -f`/`shasum`, brew bash 4+)
      - Release job on `v*` tags: GitHub Release with the extracted CHANGELOG section
      - Untested until first real tag push — `v0.3.0` will be the first exercise

## Open work (medium)

- [x] fish shell support — `pwdtintii.plugin.fish` (fish 3.5+), full native port;
      byte-identical OSC-11 + shared PID registry; `tests/fish.bats`
      comparing fish vs bash; `examples/aliases.fish`; fzf commands force
      `SHELL=/bin/sh`. ← erledigt 2026-06-18
- [x] tmux integration — per-pane background via `tmux select-pane -P "bg=#..."`;
      `pt off` resets to `bg=default`. The fzf live-preview is now per-pane too
      (the OSC-11-global limitation is fixed in the unreleased work above). ←
      erledigt 2026-06-18
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
├── pwdtintii.plugin.fish   # native fish plugin (3.5+)
├── bin/pwdtintii           # CLI companion (fzf preview helper)
├── palettes/
│   ├── default.tsv         # 37 families × 4 shades (dark themes)
│   ├── light.tsv           # pale variant for light themes
│   └── README.md
├── VERSION                 # single source of truth for the version string
├── scripts/
│   ├── contrast.py         # WCAG + APCA engine (dump + --row machine mode)
│   ├── contrast-check.sh   # WCAG + APCA check wrapper (needs python3)
│   ├── gen-light-palette.py  # regenerates light.tsv from default.tsv
│   └── release.sh          # version bump + commit + tag automation (dry-run by default)
├── tests/                  # bats suite coupling bash + zsh + fish
│   ├── helper.bash
│   ├── parity.bats         # cross-shell key/family/hash parity
│   ├── plugin.bats         # bash plugin behaviour
│   ├── cli.bats            # bin/pwdtintii subcommands
│   ├── palette.bats        # light.tsv parity + contrast-check
│   ├── fish.bats           # fish vs bash output parity
│   ├── release.bats        # scripts/release.sh behaviour
│   ├── version.bats        # pt version parity + doc-drift guard
│   ├── test_palette_math.py  # WCAG/YIQ/APCA reference checks
│   └── run.sh
├── .github/workflows/
│   └── ci.yml              # shellcheck + zsh -n + bats
├── examples/
│   ├── aliases.zsh         # opt-in pt, ptpick, ...
│   ├── aliases.bash
│   ├── aliases.fish
│   └── overrides.tsv       # template for named overrides
├── LICENSE                 # Apache-2.0
├── NOTICE
├── CHANGELOG.md
├── README.md
└── TODO.md                 # ← you are here
```
