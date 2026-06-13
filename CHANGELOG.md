# Changelog

All notable changes to pwdtintii will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.1] — 2026-06-13

### Fixed
- **fzf picker cancel** — pressing ESC no longer captured the restore OSC
  sequence into a variable; the picker now returns only the family and the
  caller restores the background, so cancel correctly reverts the tint.
- **zsh `sha1sum` fallback** — the zsh plugin hardcoded `shasum` and broke on
  Linux systems that only ship `sha1sum`; it now detects either at load (and
  fails loudly if neither is present), matching the bash plugin and the docs.
- **bash key drift** — directories outside `$HOME` collapsed to the whole path
  in bash but the first component in zsh; bash now also uses the first
  component, so both shells tint the same directory identically.
- **cross-shell registry hash** — zsh hashed the key with a trailing newline
  (`print -r`) while bash did not (`printf`), so the two never shared a shade
  registry; zsh now uses `print -rn`.
- **empty palette** — a palette with no families caused a division-by-zero on
  every prompt; `apply` is now a no-op and load warns once.
- **menu bounds** — choice `0` in the numbered picker selected the last family
  via bash negative indexing; out-of-range input is now rejected, and a
  leading-zero choice (`08`, `09`) no longer trips bash octal parsing.
- **root path** — applying at the filesystem root (`/`, empty project name) no
  longer leaks a `bad array subscript` error to the bash prompt.
- **registry race** — the read-modify-write is now guarded by a `mkdir` lock
  (bounded, fail-open) so shells starting concurrently in the same dir don't
  clobber each other's shade.
- **bash symlink resolution** — `_pwdtintii_self` now follows symlinks, so the
  plugin works when sourced via a symlink.
- registry `.t` temp files are cleaned up and emptied registries removed.
- OSC 11 emission validates the hex before emitting (no escape injection from a
  malformed palette).

### Added
- `pwdtintii_pick --auto` clears a pinned family and returns to auto mode.
- bats test harness (`tests/`) coupling the bash and zsh plugins, plus a
  Forgejo CI workflow (shellcheck, `zsh -n`, bats).

### Changed
- Steady-state prompts (same directory) skip all subprocess work and only
  re-emit, cutting ~6 forks per prompt down to the key lookup.

## [0.1.0] — 2026-05-26

### Added
- zsh plugin (`pwdtintii.plugin.zsh`) with `precmd`-driven OSC 11 emission.
- bash 4+ plugin (`pwdtintii.plugin.bash`) with `PROMPT_COMMAND` hook.
- 37-family palette (`palettes/default.tsv`) covering cool/warm/earth/neutral tones.
- Per-key PID-tracked shade registry — splits in the same dir get distinct shades.
- `pwdtintii_pick` with fzf-based live-preview picker, numbered-menu fallback.
- `pwdtintii_list` / `pwdtintii_reload` / `pwdtintii_apply` public functions.
- `bin/pwdtintii` CLI for the fzf preview pane.
- `scripts/preview.sh` — visual palette dump.
- `scripts/contrast-check.sh` — WCAG check for fg/bg combos.
- `examples/aliases.{zsh,bash}` — opt-in short aliases (`pt`, `ptpick`, …).
- `examples/overrides.tsv` — example named-overrides config.
- Apache-2.0 license.
