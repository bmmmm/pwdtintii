# Changelog

All notable changes to pwdtintii will be documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Public GitHub mirror at github.com/bmmmm/pwdtintii — one-way Forgejo→GitHub
  push-mirror, so the project can now be cloned from GitHub.
- **`pt off`** — actually stops tinting: resets the terminal background to its
  default (OSC 111) and makes the prompt hook a no-op until re-enabled via
  `pt pick` / `pt auto` / `pt reload`. Previously `off` was only an alias for
  `auto`/unpin and kept tinting by directory.
- **`pt doctor`** — reports the setup (hash command, fzf, palette, terminal) and
  probes OSC 11 support live, surfacing the otherwise-silent failure mode of a
  terminal that ignores OSC 11.
- Install via a plugin manager (oh-my-zsh / zinit / antidote), documented in the
  README — the `pwdtintii.plugin.zsh` naming already followed the convention.
- macOS coverage in CI (`macos-latest`) — exercises the BSD `stat -f` / `shasum`
  / BSD-awk / brew-bash path the project is built around, which the Linux-only
  job never touched — plus a release job that cuts a GitHub Release from the
  matching CHANGELOG section on `v*` tags.

### Changed
- CI consolidated into a single `.github/workflows/ci.yml`, read by both
  Forgejo (source of truth) and GitHub (mirror); the `.forgejo/` copy was removed.
- Install URL and copyright now reference the public GitHub identity.
- Prompt hot-path: the directory key is cached by `$PWD`, skipping the per-prompt
  subshell fork + git-root stat-walk while the directory is unchanged (a fresh
  `git init` in the current dir is picked up on the next `cd`).

### Fixed
- Palette loading validates that each family has four `#rrggbb` shades and skips
  any malformed row with a warning, instead of storing it and silently emitting
  nothing on that family.

## [0.2.0] — 2026-06-14

### Added
- **`pt` entry point** — bare `pt` opens an fzf action menu listing every
  command (with a live description in the preview pane); selecting one runs it.
  The menu loops: display-only actions (`list`, `preview`, `contrast`) pause
  afterwards — q quits the hub, any other key (including arrow keys) returns to
  the menu. ESC steps back one level: out of the family picker into the menu,
  out of the menu to the shell. The header shows the current family/shade, and
  flags a stale shell when the plugin file has changed on disk since it was
  sourced (`pt help` notes it too). `pt <cmd>` dispatches directly: `pick`,
  `list`, `auto`, `reload`, `preview`, `contrast`, `help`. Without fzf, bare
  `pt` prints a cheat-sheet.
- `bin/pwdtintii actions` / `describe-action` expose the action catalog — the
  single source of truth the shell dispatcher re-runs, so menu and dispatch
  cannot drift (guarded by a test).
- `pwdtintii_pick --auto` clears a pinned family and returns to auto mode.
- bats test harness (`tests/`) coupling the bash and zsh plugins, plus a
  Forgejo CI workflow (shellcheck, `zsh -n`, bats).

### Changed
- The `pt` alias now points at the dispatcher (was `pwdtintii_apply`, a
  visual no-op); `ptpick`/`ptlist`/… remain as direct accelerators.
- Steady-state prompts (same directory) skip all subprocess work and only
  re-emit, cutting ~6 forks per prompt down to the key lookup.
- README rewritten compact, with screenshots of the action hub and the live
  family picker (`docs/`).

### Fixed
- **fzf preview height** — the family preview now stretches to fill the pane
  (`FZF_PREVIEW_LINES`) instead of a fixed ~18 lines that left the lower half
  empty and pushed the fourth shade behind a scrollbar.
- **live focus tone** — hovering a family in the picker emitted shade2 as the
  background, so the shade2 swatch vanished into it; it now emits a dimmed
  family tone (shade0 × 50%), darker than all four shades, so each stays
  distinct.
- **emit under `set -e`** — `emit-family` no longer aborts when there is no
  controlling `/dev/tty` (the failed redirect is fully contained).
- **CLI help leak** — `pwdtintii help` (the CLI) printed `set -euo pipefail`
  from the source below the doc block; it now stops at the first blank line.
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
