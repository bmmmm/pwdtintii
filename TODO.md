# TODO — pwdtintii

Entry point for a fresh Claude session. Read this first, then pick a section.

## Status

0.1.1 — bug-fix pass over the 0.1.0 scaffold. Plugin sources, palette, fzf
picker, contrast check, README, LICENSE done; bash/zsh drift bugs fixed and
locked down with a bats suite + Forgejo CI (see CHANGELOG 0.1.1).
Dotfiles still need migration to source the plugin instead of inlining.

## Next session — start here

1. **Verify in a fresh Ghostty window**
   - Open a new tab in `~/ops`, expect tint matching `pwdtintii_list` output.
   - `cd ~/offline_coding/dotfiles` → tint should change at next prompt.
   - `cmd+d` (split) → same family, different shade.
   - Run `pwdtintii_pick` → fzf opens, arrow keys preview live, ENTER pins.
   - Run `pwdtintii_pick blue` → directly pins blue.

2. **Migrate `~/offline_coding/dotfiles/zshrc`** if not already done:
   - Remove the inline `_gbg_*` block (lines ~104–250).
   - Replace with: `source ~/offline_coding/pwdtintii/pwdtintii.plugin.zsh`.
   - Optionally: `source ~/offline_coding/pwdtintii/examples/aliases.zsh`.

3. **bash-side verify** (Linux later or via `brew install bash` on Mac):
   - `bash --rcfile <(echo "source ~/offline_coding/pwdtintii/pwdtintii.plugin.bash")`
   - Confirm `pwdtintii_list` works, OSC 11 emits on prompt.

## Open work (small)

- [ ] Demo GIF for README (asciinema → agg, or screen capture)
- [ ] Tag `v0.1.1` after Ghostty verification passes
- [ ] Add to skills-inventory if relevant
- [ ] Eventually: GitHub mirror via `/new-mirrored-repo` (currently private only)

## Open work (medium)

- [ ] fish shell support — `function --on-event fish_prompt`
- [ ] tmux integration — set per-pane background via `select-pane -P`
- [ ] Light-theme palette variant — high-luminance background set for users on
      light terminal themes

## Design decisions already made

- **License:** Apache-2.0 (per `~/ops/reference/licensing.md` decision tree —
  plugin = library + glue, not copyleft-warranted algorithm).
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
├── .forgejo/workflows/
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
